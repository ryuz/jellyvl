
// 調整機構
module jellyvl_synctimer_adjust #(
    parameter int unsigned TIMER_WIDTH = 32, // タイマのbit幅
    //    parameter LIMIT_WIDTH    : u32 = TIMER_WIDTH            , // 補正限界のbit幅
    parameter int unsigned CYCLE_WIDTH = 32, // 自クロックサイクルカウンタのbit数
    //    parameter ERROR_WIDTH    : u32 = 32                     , // 誤差計算時のbit幅
    //    parameter ERROR_Q        : u32 = 8                      , // 誤差計算時に追加する固定小数点数bit数
    //    parameter ADJUST_WIDTH   : u32 = COUNTER_WIDTH + ERROR_Q, // 補正周期のbit幅
    //    parameter ADJUST_Q       : u32 = ERROR_Q                , // 補正周期に追加する固定小数点数bit数
    //    parameter PERIOD_WIDTH   : u32 = ERROR_WIDTH            , // 周期補正に使うbit数
    //    parameter PHASE_WIDTH    : u32 = ERROR_WIDTH            , // 位相補正に使うbit数
    parameter int unsigned LPF_GAIN_CYCLE = 4, // 自クロックサイクルカウントLPFの更新ゲイン(1/2^N)
    //    parameter LPF_GAIN_PERIOD: u32 = 4                      , // 周期補正のLPFの更新ゲイン(1/2^N)
    //    parameter LPF_GAIN_PHASE : u32 = 4                      , // 位相補正のLPFの更新ゲイン(1/2^N)
    //    parameter INIT_OVERRIDE  : bit = 1                      , // 初回の補正
    parameter bit DEBUG      = 1'b0,
    parameter bit SIMULATION = 1'b0
) (
    input logic reset,
    input logic clk  ,

    //    param_limit_min : input signed logic<LIMIT_WIDTH> ,
    //    param_limit_max : input signed logic<LIMIT_WIDTH> ,
    //    param_cycle_min : input signed logic<CYCLE_WIDTH> ,
    //    param_cycle_max : input signed logic<CYCLE_WIDTH> ,
    //    param_period_min: input signed logic<PERIOD_WIDTH>,
    //    param_period_max: input signed logic<PERIOD_WIDTH>,
    //    param_phase_min : input signed logic<PHASE_WIDTH> ,
    //    param_phase_max : input signed logic<PHASE_WIDTH> ,

    input logic [TIMER_WIDTH-1:0] current_time,

    //    override_request: output logic,

    input logic                   correct_override,
    input logic [TIMER_WIDTH-1:0] correct_time    ,
    input logic                   correct_valid   ,

    output logic adjust_sign ,
    output logic adjust_valid,
    input  logic adjust_ready

);

    localparam int unsigned CYCLE_Q = LPF_GAIN_CYCLE;

    //    localparam ERROR_WIDTH = if PERIOD_WIDTH >= PHASE_WIDTH { PERIOD_WIDTH } else { PHASE_WIDTH };
    //    localparam ERROR_Q     = if LPF_GAIN_PERIOD >= LPF_GAIN_PHASE { LPF_GAIN_PERIOD } else { LPF_GAIN_PHASE };

    // type
    //    localparam t_time   : type = logic<TIMER_WIDTH>;
    localparam type t_count = logic [CYCLE_WIDTH-1:0];
    localparam type t_cycle = logic [CYCLE_WIDTH + CYCLE_Q-1:0];
    //    localparam t_period : type = signed logic<PERIOD_WIDTH>;
    //    localparam t_phase  : type = signed logic<PHASE_WIDTH>;
    //    localparam t_error  : type = signed logic<ERROR_WIDTH + ERROR_Q>;
    //    localparam t_error_u: type = logic<ERROR_WIDTH + ERROR_Q>;
    //    localparam t_adjust : type = logic<ADJUST_WIDTH + ADJUST_Q>;
    //
    //    localparam t_lpf_cycle  : type =        logic<CYCLE_WIDTH  + LPF_GAIN_CYCLE>;
    //    localparam t_lpf_period : type = signed logic<PERIOD_WIDTH + LPF_GAIN_PERIOD>;
    //    localparam t_lpf_phase  : type = signed logic<PHASE_WIDTH  + LPF_GAIN_PHASE>;
    //
    //    var param_lpf_cycle_min : t_lpf_cycle;
    //    var param_lpf_cycle_max : t_lpf_cycle;
    //    var param_lpf_period_min: t_lpf_period;
    //    var param_lpf_period_max: t_lpf_period;
    //    var param_lpf_phase_min : t_lpf_phase;
    //    var param_lpf_phase_max : t_lpf_phase;
    //
    //    assign param_lpf_cycle_min  = param_cycle_min  as t_lpf_cycle  <<< LPF_GAIN_CYCLE;
    //    assign param_lpf_cycle_max  = param_cycle_max  as t_lpf_cycle  <<< LPF_GAIN_CYCLE;
    //    assign param_lpf_period_min = param_period_min as t_lpf_period <<< LPF_GAIN_PERIOD;
    //    assign param_lpf_period_max = param_period_max as t_lpf_period <<< LPF_GAIN_PERIOD;
    //    assign param_lpf_phase_min  = param_phase_min  as t_lpf_phase  <<< LPF_GAIN_PHASE;
    //    assign param_lpf_phase_max  = param_phase_max  as t_lpf_phase  <<< LPF_GAIN_PHASE;



    //    // 固定小数点変換
    //    function TimeIntToFix (
    //        phase: input t_calc,
    //    ) -> t_error {
    //        return phase as t_error <<< ERROR_Q;
    //    }
    //
    //
    //    // 範囲パラメータ固定小数点化
    //    var error_phase_min : t_error;
    //    var error_phase_max : t_error;
    //    var error_period_min: t_error;
    //    var error_period_max: t_error;
    //    assign error_phase_min  = PhaseToAdjust(param_phase_min);
    //    assign error_phase_max  = PhaseToAdjust(param_phase_max);
    //    assign error_period_min = PeriodToAdjust(param_period_min);
    //    assign error_period_max = PeriodToAdjust(param_period_max);



    // サイクルカウント
    t_count count_cycle ;
    logic   count_enable;
    logic   count_valid ;
    always_ff @ (posedge clk) begin
        if (reset) begin
            count_cycle  <= 'x;
            count_enable <= 1'b0;
        end else begin
            count_cycle <= count_cycle + (t_count'(1));
            if (correct_valid) begin
                count_cycle  <= t_count'(1);
                count_enable <= 1'b1;
            end
        end
    end
    assign count_valid = correct_valid & count_enable;


    // １周期のサイクル数予測
    t_cycle         cycle_observe_t         ; // サイクル数の観測値
    t_cycle         cycle_predict_t         ; // サイクル数の観測値
    t_cycle         cycle_predict_t_gain    ; // 位相誤差の予測値にゲインを掛けたもの
    t_cycle         cycle_estimate_t        ; // 位相誤差の推定値
    t_cycle         cycle_estimate_t0       ; // １つ前の位相誤差の推定値
    logic           cycle_observe_t_enable  ;
    logic           cycle_estimate_t_enable ;
    logic           cycle_estimate_t0_enable;
    logic   [3-1:0] cycle_valid             ;

    assign cycle_predict_t = cycle_estimate_t0;

    always_ff @ (posedge clk) begin
        if (reset) begin
            cycle_observe_t          <= 'x;
            cycle_predict_t_gain     <= 'x;
            cycle_estimate_t         <= 'x;
            cycle_estimate_t0        <= 'x;
            cycle_observe_t_enable   <= 1'b0;
            cycle_estimate_t_enable  <= 1'b0;
            cycle_estimate_t0_enable <= 1'b0;
            cycle_valid              <= '0;
        end else begin
            if (count_valid) begin
                cycle_observe_t        <= t_cycle'(count_cycle) <<< CYCLE_Q;
                cycle_observe_t_enable <= count_enable;

                cycle_estimate_t0        <= cycle_estimate_t;
                cycle_estimate_t0_enable <= cycle_estimate_t_enable;
            end

            cycle_predict_t_gain <= cycle_predict_t - (cycle_predict_t >>> CYCLE_Q);
            if (cycle_observe_t_enable) begin
                if (cycle_estimate_t0_enable) begin
                    cycle_estimate_t <= cycle_predict_t_gain + (cycle_observe_t >>> CYCLE_Q);
                end else begin
                    cycle_estimate_t <= cycle_observe_t;
                end
                cycle_estimate_t_enable <= 1'b1;
            end

            cycle_valid <= cycle_valid >> (1);
            if (count_valid && count_enable) begin
                cycle_valid[2] <= 1'b1;
            end
        end
    end


    /*


    var observe_x      : t_error;   // 位相誤差の観測値
    var predict_x      : t_error;   // 位相誤差の予測値
    var predict_x_gain : t_error;   // 位相誤差の予測値にゲインを掛けたもの
    var estimate_x     : t_error;   // 位相誤差の推定値
    var estimate_x0    : t_error;   // １つ前の位相誤差の推定値
    var observe_v      : t_error;   // 周期誤差の観測値
    var predict_v      : t_error;   // 位相誤差の予測値
    var predict_v_gain : t_error;   // 周期誤差の予測値にゲインを掛けたもの
    var estimate_v     : t_error;   // 周期誤差の推定値
    var estimate_v0    : t_error;   // １つ前の周期誤差の推定値




    assign predict_v = estimate_v0; // 周期予測はひとつ前の推定値と同じ

    always_ff (clk, reset) {
        if_reset {

        } else {
            cycle_count = cycle_count + t_cycle;
            if correct_valid {
                cycle_count = 1 as t_cycle;
            }

            if correct_valid {
                observe_t = cycle_count;
            }
            predict_t_gain = predict_t <<< LPF_GAIN_PHASE - predict_t;
            if cycle_enable {
                estimate_x = predict_t_gain + (observe_t >>> ERROR_Q);
            }else {
                estimate_x = observe_t;
            }


            if correct_valid {
                if override {
                    estimate_x0 = '0;
                    estimate_v0 = 'x;
                    observe_x   = '0;
                    phase_enable  = 1'b1;
                    period_enable = 1'b0;
                }
                else {
                    estimate_x0 = estimate_x;
                    estimate_v0 = estimate_v;
                    observe_x   = (current_time_correct - current_time_local) as t_error <<< ERROR_Q;
                    period_enable = phase_enable;
                }
            }

            // 位相ずれ予測
            predict_x      = estimate_x + estimate_v - adj_value
            predict_x_gain = predict_x <<< LPF_GAIN_PHASE - predict_x;
            estimate_x     = predict_x_gain + (observe_x >>> ERROR_Q);

            // 周期ずれ予測
            observe_v      = estimate_x - (estimate_x0 - adj_value)
            predict_v_gain = predict_v <<< LPF_GAIN_PERIOD - predict_v;
            estimate_v     = predict_v_gain + (observe_v >>> ERROR_Q);
        }
    }


    // stage 1
    var st1_error_phase : t_phase ;
    var st1_error_period: t_period;
    var st1_enable      : logic   ;

    var st1_valid       : logic   ;

    always_ff (clk, reset) {
        if_reset {
            st1_error_phase  = 'x;
            st1_error_period = 'x;
            st1_enable       = 1'b0;
            st1_valid        = 1'b0;
        } else {
            if st0_valid {
                st1_predict_x
                
                error_phase  = (st0_time_correct - st0_time_local) as t_phase;
                st1_error_period = (st0_period_correct - st0_period_local) as t_period;
                st1_error_enable = st0_enable;
            }
            st1_valid = st0_valid;
        }
    }

    // stage 2
    var st2_cycle_count : t_cycle;
    var st2_error_period: t_period;
    var st2_error_phase : t_phase;
    var st2_enable      : logic  ;
    var st2_valid       : logic  ;

    always_ff (clk, reset) {
        if_reset {
            st2_cycle_count  = 'x;
            st2_error_period = 'x;
            st2_error_phase  = 'x;
            st2_enable       = 1'b0;
            st2_valid        = 1'b0;
        } else {
            st2_count += 1'b1;
            if st2_valid {
                st2_cycle_count = 1 as t_cycle;
            }

            // 今回周期補償する分を、位相誤差誤差から取り除く
            st2_error_period = st1_error_period + (lpf_error_phase >>> LPF_GAIN_PHASE) as t_period;
            st2_error_phase  = st1_error_phase;
            st2_valid        = st1_valid && st1_enable;
        }
    }

    // stage 3
    var lpf_pre_cycle_count  : t_lpf_cycle ;
    var lpf_pre_error_period : t_lpf_period ;
    var lpf_pre_error_phase  : t_lpf_phase ;
    var lpf_enable           : logic;

    var st3_error_phase : t_error;
    var st3_error_period: t_error;
    var st3_valid       : logic  ;

    always_ff (clk, reset) {
        if_reset {
            lpf_pre_cycle_count  = 'x;
            lpf_pre_error_period = 'x;
            lpf_pre_error_phase  = 'x;
            lpf_cycle_count      = 'x;
            lpf_error_period     = 'x;
            lpf_error_phase      = 'x;
            lpf_enable           = 1'b0;

            st3_enable       = 1'b0;
            st3_valid        = 1'b0;
        } else {
            // LPF
            lpf_pre_cycle_count  = (lpf_cycle_count  <<  LPF_GAIN_CYCLE)  - lpf_cycle_count;
            lpf_pre_error_period = (lpf_error_period <<< LPF_GAIN_PERIOD) - lpf_error_period;
            lpf_pre_error_phase  = (lpf_error_phase  <<< LPF_GAIN_PHASE)  - lpf_error_phase;
            if st2_enable {
                lpf_enable = 1'b1;
                if lpf_enable {
                    lpf_cycle_count   = lpf_pre_cycle_count + st2_sycle_count;
                    lpf_error_period = lpf_pre_error_period + st2_error_period;
                    lpf_error_phase  = lpf_pre_error_phase  + st2_error_phase ;
                }
                else {
                    lpf_cycle_count  = st2_cycle_count;
                    lpf_error_period = st2_error_period;
                    lpf_error_phase  = st2_error_phase ;
                }
            }
            st3_valid  = st2_valid;
        }
    }


    // stage 4
    var st4_cycle_count  : t_lpf_cycle ;
    var st4_error_period : t_lpf_period ;
    var st4_error_phase  : t_lpf_phase ;
    var st4_enable       : logic  ;
    var st4_valid        : logic  ;
    
    always_ff (clk, reset) {
        if_reset {
            st4_cycle_count  = 'x;
            st4_error_period = 'x;
            st4_error_phase  = 'x;
            st3_enable       = 'x;
            st3_valid        = 1'b0;
        } else {
            st4_cycle_count  = lpf_cycle_count ;
            st4_error_period = lpf_error_period;
            st4_error_phase  = lpf_error_phase ;
            st4_enable       = st3_enable      ;
            st4_valid        = st3_valid       ;

            if lpf_cycle_count  <: param_lpf_cycle_min  { st4_cycle_count = param_lpf_cycle_min; }
            if lpf_cycle_count  >: param_lpf_cycle_max  { st4_cycle_count = param_lpf_cycle_max; }
            if st4_error_period <: param_lpf_period_min { st4_error_period = param_lpf_period_min; }
            if st4_error_period >: param_lpf_period_max { st4_error_period = param_lpf_period_max; }
            if st4_error_phase  <: param_lpf_phase_min  { st4_error_phase = param_lpf_phase_min; }
            if st4_error_phase  >: param_lpf_phase_max  { st4_error_phase = param_lpf_phase_max; }
        }
    }


    // stage 5
    var st5_cycle_count  : t_lpf_cycle ;
    var st5_error_period : t_lpf_period ;
    var st5_error_phase  : t_lpf_phase ;
    var st5_enable       : logic  ;
    var st5_valid        : logic  ;
    
    always_ff (clk, reset) {
        if_reset {
            st5_cycle_count  = 'x;
            st5_error_period = 'x;
            st5_error_phase  = 'x;
            st5_enable       = 'x;
            st5_valid        = 1'b0;
        } else {
            st5_cycle_count  = st4_cycle_count ;
            st5_error_period = st4_error_period;
            st5_error_phase  = st4_error_phase ;
            st5_enable       = st4_enable      ;
            st5_valid        = st4_valid       ;
        }
    }

    // stage 5
    var st5_adjust_total: t_lpferror;
    var st5_adjust_total: t_error;
    var st5_change_total: t_error;
    var st5_valid       : logic  ;

    always_ff (clk, reset) {
        if_reset {
            st5_adjust_total = 'x;
            st5_change_total = 'x;
            st5_enable       = 1'b0;
            st5_valid        = 1'b0;
        } else {
            st5_adjust_total = st4_adjust_period + st4_adjust_phase;
            st5_change_total = st4_change_period + st4_change_phase;
            st5_enable       = st4_enable;
            st5_valid        = st4_valid;
        }
    }

    // stage 6
    var st6_count : t_error_u; // 自クロックでの経過時刻計測
    var st6_adjust: t_error_u;
    var st6_sign  : logic    ;
    var st6_zero  : logic    ;
    var st6_enable: logic    ;
    var st6_valid : logic    ;

    always_ff (clk, reset) {
        if_reset {
            st6_sign   = 'x;
            st6_zero   = 'x;
            st6_adjust = 'x;
            st6_count  = 'x;
            st6_enable = 1'b0;
            st6_valid  = 1'b0;
        } else {
            st6_count += 1'b1;
            if st6_valid {
                st6_count = '0;
            }

            if st5_valid {
                st6_sign   = st5_adjust_total <: 0;
                st6_zero   = st5_adjust_total == 0;
                st6_adjust = if st5_adjust_total <: 0 {
                    (-st5_adjust_total) as t_error_u
                } else {
                    st5_adjust_total as t_error_u
                };
            }
            st6_enable = st5_valid & st5_enable;
            st6_valid  = st5_valid;
        }
    }

    always_ff (clk, reset) {
        if_reset {
            next_change_total = 'x;
            next_change_valid = 1'b0;
        } else {
            next_change_total = AdjustToCalc(st5_change_total);
            next_change_valid = st5_valid & st5_enable;
        }
    }


    // divider
    var div_quotient : t_adjust ;
    var div_remainder: t_error_u;
    var div_valid    : logic    ;

    var tmp_ready: logic;
    inst i_divider_unsigned_multicycle: divider_unsigned_multicycle #(
        DIVIDEND_WIDTH: COUNTER_WIDTH + ERROR_Q,
        DIVISOR_WIDTH : ERROR_WIDTH + ERROR_Q  ,
        QUOTIENT_WIDTH: ADJUST_WIDTH + ADJUST_Q,
    ) (
        reset: reset,
        clk  : clk  ,
        cke  : 1'b1 ,

        s_dividend: st6_count as t_count_q << (ERROR_Q + ADJUST_Q),
        s_divisor : st6_adjust                                  ,
        s_valid   : st6_enable                                  ,
        s_ready   : tmp_ready                                   ,

        m_quotient : div_quotient ,
        m_remainder: div_remainder,
        m_valid    : div_valid    ,
        m_ready    : 1'b1         ,
    );


    // adjust parameter
    localparam ADJ_STEP: t_adjust = (1 << ADJUST_Q) as t_adjust;

    var adj_param_zero  : logic   ;
    var adj_param_sign  : logic   ;
    var adj_param_period: t_adjust;
    var adj_param_valid : logic   ;
    var adj_param_ready : logic   ;

    always_ff (clk, reset) {
        if_reset {
            adj_param_zero   = 1'b1;
            adj_param_sign   = 1'bx;
            adj_param_period = 'x;
            adj_param_valid  = 1'b0;
        } else {
            if adj_param_ready {
                adj_param_valid = 1'b0;
            }

            if div_valid {
                if st6_zero {
                    adj_param_zero   = 1'b1;
                    adj_param_sign   = 1'b0;
                    adj_param_period = '0;
                    adj_param_valid  = !adj_param_zero; // 変化があれば発行
                } else {
                    adj_param_zero   = st6_zero;
                    adj_param_sign   = st6_sign;
                    adj_param_period = div_quotient - ADJ_STEP;
                    adj_param_valid  = adj_param_zero || ((div_quotient - ADJ_STEP) != adj_param_period);
                }
            }
        }
    }

    // adjuster
    var adj_calc_zero  : logic   ;
    var adj_calc_sign  : logic   ;
    var adj_calc_period: t_adjust;
    var adj_calc_count : t_adjust;
    var adj_calc_next  : t_adjust;
    var adj_calc_valid : logic   ;

    always_ff (clk, reset) {
        if_reset {
            adj_calc_zero   = 1'b1;
            adj_calc_sign   = 'x;
            adj_calc_period = '0;
            adj_calc_count  = 'x;
            adj_calc_next   = 'x;
            adj_calc_valid  = 1'b0;
        } else {

            // adj_param_valid は連続で来ない、period は2以上の前提で事前計算
            adj_calc_count += (1 << ADJUST_Q) as t_adjust;
            adj_calc_next  =  adj_calc_count - adj_calc_period;
            adj_calc_valid =  adj_calc_count >= adj_calc_period;

            if adj_calc_valid {
                if adj_param_valid {
                    adj_calc_zero   = adj_param_zero;
                    adj_calc_sign   = adj_param_sign;
                    adj_calc_period = adj_param_period;
                    adj_calc_count  = '0;
                } else {
                    adj_calc_count = adj_calc_next;
                }
            }
        }
    }

    assign adj_param_ready = adj_calc_valid;


    // output
    always_ff (clk, reset) {
        if_reset {
            adjust_sign  = 'x;
            adjust_valid = 1'b0;
        } else {
            if adjust_ready {
                adjust_valid = 1'b0;
            }

            if adj_calc_valid {
                adjust_sign  = adj_calc_sign;
                adjust_valid = ~adj_calc_zero;
            }
        }
    }

    if SIMULATION :sim_monitor {
        var sim_monitor_time_local            : t_calc  ;
        var sim_monitor_time_correct          : t_calc  ;
        var sim_monitor_period_local          : t_calc  ;
        var sim_monitor_period_correct        : t_calc  ;
        var sim_monitor_error_phase           : t_phase ;
        var sim_monitor_error_period          : t_period;
        var sim_monitor_corrected_error_phase : real    ;
        var sim_monitor_corrected_error_period: real    ;
        var sim_monitor_adjust_phase          : real    ;
        var sim_monitor_adjust_period         : real    ;
        var sim_monitor_adjust_total          : real    ;

        always_ff (clk) {
            if correct_valid {
                sim_monitor_time_local   = current_time_local;
                sim_monitor_time_correct = current_time_correct;
            }
            if st3_valid {
                sim_monitor_corrected_error_phase  = $itor(st3_error_phase) / $itor(2 ** ERROR_Q);
                sim_monitor_corrected_error_period = $itor(st3_corrected_error_period) / $itor(2 ** ERROR_Q);
            }
        }

        assign sim_monitor_period_correct = st0_period_correct;
        assign sim_monitor_period_local   = st0_period_local;
        assign sim_monitor_error_phase    = st1_error_phase;
        assign sim_monitor_error_period   = st1_error_period;
        assign sim_monitor_adjust_phase   = $itor(st4_adjust_phase) / $itor(2 ** ERROR_Q);
        assign sim_monitor_adjust_period  = $itor(st4_adjust_period) / $itor(2 ** ERROR_Q);
        assign sim_monitor_adjust_total   = $itor(st5_adjust_total) / $itor(2 ** ERROR_Q);
    }
    */

    if (SIMULATION) begin :sim_monitor
        real sim_monitor_cycle_estimate_t;

        assign sim_monitor_cycle_estimate_t = $itor(cycle_estimate_t) / $itor(2 ** CYCLE_Q);
    end

endmodule
