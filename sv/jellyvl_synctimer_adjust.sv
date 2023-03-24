
// 調整機構
module jellyvl_synctimer_adjust #(
    parameter int unsigned TIMER_WIDTH = 32, // タイマのbit幅
    //    parameter LIMIT_WIDTH    : u32 = TIMER_WIDTH            , // 補正限界のbit幅
    parameter int unsigned CYCLE_WIDTH  = 32                   , // 自クロックサイクルカウンタのbit数
    parameter int unsigned ERROR_WIDTH  = 32                   , // 誤差計算時のbit幅
    parameter int unsigned ERROR_Q      = 8                    , // 誤差計算時に追加する固定小数点数bit数
    parameter int unsigned ADJUST_WIDTH = CYCLE_WIDTH + ERROR_Q, // 補正周期のbit幅
    parameter int unsigned ADJUST_Q     = ERROR_Q              , // 補正周期に追加する固定小数点数bit数
    //    parameter PERIOD_WIDTH   : u32 = ERROR_WIDTH            , // 周期補正に使うbit数
    //    parameter PHASE_WIDTH    : u32 = ERROR_WIDTH            , // 位相補正に使うbit数
    parameter int unsigned LPF_GAIN_CYCLE  = 2, // 自クロックサイクルカウントLPFの更新ゲイン(1/2^N)
    parameter int unsigned LPF_GAIN_PERIOD = 2, // 周期補正のLPFの更新ゲイン(1/2^N)
    parameter int unsigned LPF_GAIN_PHASE  = 2, // 位相補正のLPFの更新ゲイン(1/2^N)
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
    localparam type t_error   = logic signed [ERROR_WIDTH + ERROR_Q-1:0];
    localparam type t_error_u = logic [ERROR_WIDTH + ERROR_Q-1:0];
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

    t_error adj_value;


    // -------------------------------------
    //  一周期の自クロックのサイクル数推定
    // -------------------------------------

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
    t_cycle cycle_observe_t        ; // サイクル数の観測値
    logic   cycle_observe_t_en     ;
    t_cycle cycle_predict_t        ; // サイクル数の観測値
    logic   cycle_predict_t_en     ;
    t_cycle cycle_predict_t_gain   ; // 位相誤差の予測値にゲインを掛けたもの
    logic   cycle_predict_t_gain_en;
    t_cycle cycle_estimate_t       ; // 位相誤差の推定値
    logic   cycle_estimate_t_en    ;
    t_cycle cycle_estimate_t0      ; // １つ前の位相誤差の推定値
    logic   cycle_estimate_t0_en   ;

    assign cycle_predict_t    = cycle_estimate_t0;
    assign cycle_predict_t_en = cycle_estimate_t0_en;

    always_ff @ (posedge clk) begin
        if (reset) begin
            cycle_observe_t         <= 'x;
            cycle_observe_t_en      <= 1'b0;
            cycle_predict_t_gain    <= 'x;
            cycle_predict_t_gain_en <= 1'b0;
            cycle_estimate_t        <= 'x;
            cycle_estimate_t_en     <= 1'b0;
            cycle_estimate_t0       <= 'x;
            cycle_estimate_t0_en    <= 1'b0;
        end else begin
            if (count_valid) begin
                // 観測値ラッチ
                cycle_observe_t    <= t_cycle'(count_cycle) <<< CYCLE_Q;
                cycle_observe_t_en <= count_enable;

                // １つ前の値保存
                cycle_estimate_t0    <= cycle_estimate_t;
                cycle_estimate_t0_en <= cycle_estimate_t_en;
            end

            // LPFをかけて推定値とする
            cycle_predict_t_gain    <= cycle_predict_t - (cycle_predict_t >>> CYCLE_Q);
            cycle_predict_t_gain_en <= cycle_predict_t_en;
            if (cycle_observe_t_en) begin
                if (cycle_predict_t_gain_en) begin
                    cycle_estimate_t <= cycle_predict_t_gain + (cycle_observe_t >>> CYCLE_Q);
                end else begin
                    cycle_estimate_t <= cycle_observe_t; // 初回のみ計測値そのまま
                end
                cycle_estimate_t_en <= cycle_observe_t_en;
            end
        end
    end



    // -------------------------------------
    //  時計の誤差修正
    // -------------------------------------

    // 誤差推定
    t_error error_observe_x        ; // 位相誤差の観測値
    logic   error_observe_x_en     ;
    t_error error_predict_x        ; // 位相誤差の予測値
    logic   error_predict_x_en     ;
    t_error error_predict_x_gain   ; // 位相誤差の予測値にゲインを掛けたもの
    logic   error_predict_x_gain_en;
    t_error error_estimate_x       ; // 位相誤差の推定値
    logic   error_estimate_x_en    ;
    t_error error_estimate_x0      ; // １つ前の位相誤差の推定値
    logic   error_estimate_x0_en   ;
    t_error error_observe_v        ; // 周期誤差の観測値
    logic   error_observe_v_en     ;
    t_error error_predict_v        ; // 位相誤差の予測値
    logic   error_predict_v_en     ;
    t_error error_predict_v_gain   ; // 周期誤差の予測値にゲインを掛けたもの
    logic   error_predict_v_gain_en;
    t_error error_estimate_v       ; // 周期誤差の推定値
    logic   error_estimate_v_en    ;
    t_error error_estimate_v0      ; // １つ前の周期誤差の推定値
    logic   error_estimate_v0_en   ;

    assign error_predict_v    = error_estimate_v0; // 周期予測はひとつ前の推定値と同じ
    assign error_predict_v_en = error_estimate_v0_en;

    always_ff @ (posedge clk) begin
        if (reset) begin
            error_observe_x         <= 'x;
            error_observe_x_en      <= 1'b0;
            error_predict_x         <= 'x;
            error_predict_x_en      <= 1'b0;
            error_predict_x_gain    <= 'x;
            error_predict_x_gain_en <= 1'b0;
            error_estimate_x        <= 'x;
            error_estimate_x_en     <= 1'b0;
            error_estimate_x0       <= 'x;
            error_estimate_x0_en    <= 1'b0;
            error_observe_v         <= 'x;
            error_observe_v_en      <= 1'b0;
            error_predict_v_gain    <= 'x;
            error_predict_v_gain_en <= 1'b0;
            error_estimate_v        <= 'x;
            error_estimate_v_en     <= 1'b0;
            error_estimate_v0       <= 'x;
            error_estimate_v0_en    <= 1'b0;
        end else begin

            if (correct_valid) begin
                if (correct_override) begin
                    error_observe_x         <= '0;
                    error_observe_x_en      <= 1'b1;
                    error_predict_x         <= 'x;
                    error_predict_x_en      <= 1'b0;
                    error_predict_x_gain    <= 'x;
                    error_predict_x_gain_en <= 1'b0;
                    error_estimate_x        <= 'x;
                    error_estimate_x_en     <= 1'b0;
                    error_estimate_x0       <= 'x;
                    error_estimate_x0_en    <= 1'b0;
                    error_observe_v         <= 'x;
                    error_observe_v_en      <= 1'b0;
                    error_predict_v_gain    <= 'x;
                    error_predict_v_gain_en <= 1'b0;
                    error_estimate_v        <= 'x;
                    error_estimate_v_en     <= 1'b0;
                    error_estimate_v0       <= 'x;
                    error_estimate_v0_en    <= 1'b0;
                end else begin
                    // 観測値ラッチ
                    error_observe_x    <= (t_error'((correct_time - current_time)) <<< ERROR_Q);
                    error_observe_x_en <= 1'b1;

                    // 1つ前の予測保存
                    error_estimate_x0    <= error_estimate_x;
                    error_estimate_x0_en <= error_estimate_x_en;

                    error_estimate_v0    <= error_estimate_v;
                    error_estimate_v0_en <= error_estimate_v_en;

                end
            end

            // 位相ずれ推定
            error_predict_x    <= error_estimate_x0 + error_estimate_v0 - t_error'(adj_value);
            error_predict_x_en <= error_estimate_x0_en & error_estimate_v0_en;

            error_predict_x_gain    <= error_predict_x - (error_predict_x >>> LPF_GAIN_PHASE);
            error_predict_x_gain_en <= error_predict_x_en;

            if (error_observe_x_en) begin
                if (error_predict_x_gain_en) begin
                    error_estimate_x <= error_predict_x_gain + (error_observe_x >>> LPF_GAIN_PHASE);
                end else begin
                    error_estimate_x <= error_observe_x;
                end
                error_estimate_x_en <= 1'b1;
            end

            // 周期ずれ推定
            error_observe_v    <= error_estimate_x - (error_estimate_x0 - t_error'(adj_value));
            error_observe_v_en <= error_estimate_x_en && error_estimate_x0_en;

            error_predict_v_gain    <= error_predict_v - (error_predict_v >>> LPF_GAIN_PERIOD);
            error_predict_v_gain_en <= error_predict_v_en;

            if (error_observe_v_en) begin
                if (error_predict_v_gain_en) begin
                    error_estimate_v <= error_predict_v_gain + (error_observe_v >>> LPF_GAIN_PHASE);
                end else begin
                    error_estimate_v <= error_observe_v;
                end
                error_estimate_v_en <= 1'b1;
            end
        end
    end

    logic [6-1:0] error_calc_delay;
    logic         error_valid     ;
    always_ff @ (posedge clk) begin
        if (reset) begin
            error_calc_delay <= '0;
        end else begin
            error_calc_delay <= error_calc_delay << (1);
            if (correct_valid) begin
                error_calc_delay[0] <= 1;
            end
        end
    end
    assign error_valid = error_calc_delay[5] & error_estimate_v_en;




    // -------------------------------------
    //  調整信号の間隔計算
    // -------------------------------------

    logic     div_calc_sign  ;
    logic     div_calc_zero  ;
    t_error_u div_calc_error ;
    t_cycle   div_calc_cycle ;
    logic     div_calc_enable;
    logic     div_calc_valid ;

    always_ff @ (posedge clk) begin
        if (reset) begin
            div_calc_sign   <= 'x;
            div_calc_zero   <= 'x;
            div_calc_error  <= 'x;
            div_calc_cycle  <= 'x;
            div_calc_enable <= 1'b0;
            div_calc_valid  <= 1'b0;
        end else begin
            if (error_valid) begin
                div_calc_sign  <= error_estimate_x < 0;
                div_calc_zero  <= error_estimate_x == 0;
                div_calc_error <= ((error_estimate_x < 0) ? (
                    t_error_u'((-error_estimate_x))
                ) : (
                    t_error_u'(error_estimate_x)
                ));
                div_calc_cycle  <= cycle_estimate_t;
                div_calc_enable <= 1'b1;
            end
            div_calc_valid <= error_valid;
        end
    end


    // divider
    localparam type t_cycle_q = logic [CYCLE_WIDTH + ERROR_Q-1:0];

    function automatic t_cycle_q CycleToError(
        input t_cycle cycle
    ) ;
        if (ERROR_Q > CYCLE_Q) begin
            return t_cycle_q'(cycle) << (ERROR_Q - CYCLE_Q);
        end else begin
            return t_cycle_q'(cycle) >> (CYCLE_Q - ERROR_Q);
        end
    endfunction

    t_adjust div_quotient ;
    t_cycle  div_remainder;
    logic    div_valid    ;

    logic tmp_ready;
    jellyvl_divider_unsigned_multicycle #(
        .DIVIDEND_WIDTH (CYCLE_WIDTH + ERROR_Q  ),
        .DIVISOR_WIDTH  (ERROR_WIDTH + ERROR_Q  ),
        .QUOTIENT_WIDTH (ADJUST_WIDTH + ADJUST_Q)
    ) i_divider_unsigned_multicycle (
        .reset (reset),
        .clk   (clk  ),
        .cke   (1'b1 ),
        .
        s_dividend (CycleToError(div_calc_cycle) << ADJUST_Q),
        .s_divisor  (div_calc_error                          ),
        .s_valid    (div_calc_valid                          ),
        .s_ready    (tmp_ready                               ),
        .
        m_quotient  (div_quotient ),
        .m_remainder (div_remainder),
        .m_valid     (div_valid    ),
        .m_ready     (1'b1         )
    );


    // adjust parameter
    localparam t_adjust ADJ_STEP = t_adjust'((1 << ADJUST_Q));

    logic    adj_param_zero  ;
    logic    adj_param_sign  ;
    t_adjust adj_param_period;
    logic    adj_param_valid ;
    logic    adj_param_ready ;

    always_ff @ (posedge clk) begin
        if (reset) begin
            adj_param_zero   <= 1'b1;
            adj_param_sign   <= 1'bx;
            adj_param_period <= 'x;
            adj_param_valid  <= 1'b0;
        end else begin
            if (adj_param_ready) begin
                adj_param_valid <= 1'b0;
            end

            if (div_valid) begin
                if (div_calc_zero) begin
                    adj_param_zero   <= 1'b1;
                    adj_param_sign   <= 1'b0;
                    adj_param_period <= '0;
                    adj_param_valid  <= !adj_param_zero; // 変化があれば発行
                end else begin
                    adj_param_zero   <= div_calc_zero;
                    adj_param_sign   <= div_calc_sign;
                    adj_param_period <= div_quotient - ADJ_STEP;
                    adj_param_valid  <= adj_param_zero || ((div_quotient - ADJ_STEP) != adj_param_period);
                end
            end
        end
    end

    // adjuster
    logic    adj_calc_zero  ;
    logic    adj_calc_sign  ;
    t_adjust adj_calc_period;
    t_adjust adj_calc_count ;
    t_adjust adj_calc_next  ;
    logic    adj_calc_valid ;

    always_ff @ (posedge clk) begin
        if (reset) begin
            adj_calc_zero   <= 1'b1;
            adj_calc_sign   <= 'x;
            adj_calc_period <= '0;
            adj_calc_count  <= 'x;
            adj_calc_next   <= 'x;
            adj_calc_valid  <= 1'b0;
        end else begin

            // adj_param_valid は連続で来ない、period は2以上の前提で事前計算
            adj_calc_count <= adj_calc_count + (t_adjust'((1 << ADJUST_Q)));
            adj_calc_next  <=  adj_calc_count - adj_calc_period;
            adj_calc_valid <=  adj_calc_count >= adj_calc_period;

            if (adj_calc_valid) begin
                if (adj_param_valid) begin
                    adj_calc_zero   <= adj_param_zero;
                    adj_calc_sign   <= adj_param_sign;
                    adj_calc_period <= adj_param_period;
                    adj_calc_count  <= '0;
                end else begin
                    adj_calc_count <= adj_calc_next;
                end
            end
        end
    end

    assign adj_param_ready = adj_calc_valid;


    // output
    always_ff @ (posedge clk) begin
        if (reset) begin
            adjust_sign  <= 'x;
            adjust_valid <= 1'b0;
        end else begin
            if (adjust_ready) begin
                adjust_valid <= 1'b0;
            end

            if (adj_calc_valid) begin
                adjust_sign  <= adj_calc_sign;
                adjust_valid <= ~adj_calc_zero;
            end
        end
    end

    /*

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
        //        var sim_monitor_error_estimate_x: real;
        //        var sim_monitor_error_estimate_v: real;

        real sim_monitor_error_observe_x     ; // 位相誤差の観測値
        real sim_monitor_error_predict_x     ; // 位相誤差の予測値
        real sim_monitor_error_predict_x_gain; // 位相誤差の予測値にゲインを掛けたもの
        real sim_monitor_error_estimate_x    ; // 位相誤差の推定値
        real sim_monitor_error_estimate_x0   ; // １つ前の位相誤差の推定値
        real sim_monitor_error_observe_v     ; // 周期誤差の観測値
        real sim_monitor_error_predict_v     ; // 位相誤差の予測値
        real sim_monitor_error_predict_v_gain; // 周期誤差の予測値にゲインを掛けたもの
        real sim_monitor_error_estimate_v    ; // 周期誤差の推定値
        real sim_monitor_error_estimate_v0   ; // １つ前の周期誤差の推定値

        assign sim_monitor_cycle_estimate_t = $itor(cycle_estimate_t) / $itor(2 ** CYCLE_Q);
        //        assign sim_monitor_error_estimate_x = $itor(error_estimate_x) / $itor(2 ** ERROR_Q);
        //        assign sim_monitor_error_estimate_v = $itor(error_estimate_v) / $itor(2 ** ERROR_Q);

        assign sim_monitor_error_observe_x      = $itor(error_observe_x) / $itor(2 ** ERROR_Q);
        assign sim_monitor_error_predict_x      = $itor(error_predict_x) / $itor(2 ** ERROR_Q);
        assign sim_monitor_error_predict_x_gain = $itor(error_predict_x_gain) / $itor(2 ** ERROR_Q);
        assign sim_monitor_error_estimate_x     = $itor(error_estimate_x) / $itor(2 ** ERROR_Q);
        assign sim_monitor_error_estimate_x0    = $itor(error_estimate_x0) / $itor(2 ** ERROR_Q);
        assign sim_monitor_error_observe_v      = $itor(error_observe_v) / $itor(2 ** ERROR_Q);
        assign sim_monitor_error_predict_v      = $itor(error_predict_v) / $itor(2 ** ERROR_Q);
        assign sim_monitor_error_predict_v_gain = $itor(error_predict_v_gain) / $itor(2 ** ERROR_Q);
        assign sim_monitor_error_estimate_v     = $itor(error_estimate_v) / $itor(2 ** ERROR_Q);
        assign sim_monitor_error_estimate_v0    = $itor(error_estimate_v0) / $itor(2 ** ERROR_Q);

    end

endmodule
