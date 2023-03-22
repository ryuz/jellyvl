
// 調整機構
module jellyvl_synctimer_adjust #(
    parameter int unsigned TIMER_WIDTH     = 64                     , // タイマのbit幅
    parameter int unsigned LIMIT_WIDTH     = TIMER_WIDTH            , // 補正限界のbit幅
    parameter int unsigned COUNTER_WIDTH   = 32                     , // 自クロックで経過時間カウンタのbit数
    parameter int unsigned CALC_WIDTH      = 32                     , // タイマのうち計算に使う部分
    parameter int unsigned ERROR_WIDTH     = 32                     , // 誤差計算時のbit幅
    parameter int unsigned ERROR_Q         = 8                      , // 誤差計算時に追加する固定小数点数bit数
    parameter int unsigned ADJUST_WIDTH    = COUNTER_WIDTH + ERROR_Q, // 補正周期のbit幅
    parameter int unsigned ADJUST_Q        = ERROR_Q                , // 補正周期に追加する固定小数点数bit数
    parameter int unsigned PERIOD_WIDTH    = ERROR_WIDTH            , // 周期補正に使うbit数
    parameter int unsigned PHASE_WIDTH     = ERROR_WIDTH            , // 位相補正に使うbit数
    parameter int unsigned PERIOD_LPF_GAIN = 4                      , // 周期補正のLPFの更新ゲイン(1/2^N)
    parameter int unsigned PHASE_LPF_GAIN  = 4                      , // 位相補正のLPFの更新ゲイン(1/2^N)
    parameter bit          INIT_OVERRIDE   = 1                      , // 初回の補正
    parameter bit          DEBUG           = 1'b0                   ,
    parameter bit          SIMULATION      = 1'b0               
) (
    input logic reset,
    input logic clk  ,

    input logic signed [LIMIT_WIDTH-1:0]  param_limit_min ,
    input logic signed [LIMIT_WIDTH-1:0]  param_limit_max ,
    input logic signed [PHASE_WIDTH-1:0]  param_phase_min ,
    input logic signed [PHASE_WIDTH-1:0]  param_phase_max ,
    input logic signed [PERIOD_WIDTH-1:0] param_period_min,
    input logic signed [PERIOD_WIDTH-1:0] param_period_max,

    input logic [TIMER_WIDTH-1:0] current_time,

    output logic override_request,

    input logic                   correct_override,
    input logic [TIMER_WIDTH-1:0] correct_time    ,
    input logic                   correct_valid   ,

    output logic adjust_sign ,
    output logic adjust_valid,
    input  logic adjust_ready

);

    // type
    localparam type t_diff    = logic signed [TIMER_WIDTH-1:0];
    localparam type t_count   = logic [COUNTER_WIDTH-1:0];
    localparam type t_count_q = logic [COUNTER_WIDTH + ADJUST_Q-1:0];
    localparam type t_calc    = logic [CALC_WIDTH-1:0];
    localparam type t_period  = logic signed [PERIOD_WIDTH-1:0];
    localparam type t_phase   = logic signed [PHASE_WIDTH-1:0];
    localparam type t_error   = logic signed [ERROR_WIDTH + ERROR_Q-1:0];
    localparam type t_error_u = logic [ERROR_WIDTH + ERROR_Q-1:0];
    localparam type t_adjust  = logic [ADJUST_WIDTH + ADJUST_Q-1:0];


    // 固定小数点変換
    function automatic t_error PhaseToAdjust(
        input t_phase phase
    ) ;
        return t_error'(phase) <<< ERROR_Q;
    endfunction

    function automatic t_error PeriodToAdjust(
        input t_period period
    ) ;
        return t_error'(period) <<< ERROR_Q;
    endfunction

    function automatic t_calc AdjustToCalc(
        input t_error adjust
    ) ;
        adjust >>>= ERROR_Q;
        return t_calc'(adjust);
    endfunction

    // 範囲パラメータ固定小数点化
    t_error error_phase_min ;
    t_error error_phase_max ;
    t_error error_period_min;
    t_error error_period_max;
    assign error_phase_min  = PhaseToAdjust(param_phase_min);
    assign error_phase_max  = PhaseToAdjust(param_phase_max);
    assign error_period_min = PeriodToAdjust(param_period_min);
    assign error_period_max = PeriodToAdjust(param_period_max);


    // リミッターによる補正要求
    logic override;
    assign override = correct_override || override_request;

    t_diff diff_time ;
    logic  diff_valid;
    always_ff @ (posedge clk) begin
        if (reset) begin
            diff_time        <= 'x;
            diff_valid       <= 1'b0;
            override_request <= INIT_OVERRIDE;
        end else begin
            diff_time  <= t_diff'((correct_time - current_time));
            diff_valid <= correct_valid && !override;

            if (correct_valid) begin
                override_request <= 1'b0;
            end

            if (diff_valid) begin
                if (diff_time < t_diff'(param_limit_min) || diff_time > t_diff'(param_limit_max)) begin
                    override_request <= 1'b1;
                end
            end
        end
    end


    // input
    t_calc current_time_local  ;
    t_calc current_time_correct;
    assign current_time_local   = t_calc'(current_time);
    assign current_time_correct = t_calc'(correct_time);

    // change
    t_calc next_change_total;
    logic  next_change_valid;


    // stage 0
    t_calc  st0_previus_local_time  ;
    t_calc  st0_previus_correct_time;
    logic   st0_previus_enable      ;
    t_calc  st0_period_local        ;
    t_calc  st0_period_correct      ;
    logic   st0_period_enable       ;
    t_phase st0_error_phase         ;
    logic   st0_valid               ;

    always_ff @ (posedge clk) begin
        if (reset) begin
            st0_previus_local_time   <= 'x;
            st0_previus_correct_time <= 'x;
            st0_previus_enable       <= 1'b0;
            st0_period_local         <= 'x;
            st0_period_correct       <= 'x;
            st0_period_enable        <= 1'b0;
            st0_error_phase          <= 'x;
            st0_valid                <= 1'b0;
        end else begin
            st0_valid <= correct_valid;

            // 補正追加分基準を補正する
            if (next_change_valid) begin
                st0_previus_local_time <= st0_previus_local_time + (next_change_total);
            end

            if (correct_valid) begin
                // 前回の時刻の記録
                st0_previus_local_time   <= current_time_local;
                st0_previus_correct_time <= current_time_correct;
                st0_previus_enable       <= 1'b1;

                // 前回との期間を算出
                st0_period_local   <= current_time_local - st0_previus_local_time;
                st0_period_correct <= current_time_correct - st0_previus_correct_time;
                st0_period_enable  <= st0_previus_enable; // 前回時刻が有効なら期間有効

                // 時刻の上書き
                if (override) begin
                    st0_previus_local_time <= current_time_correct;
                    //                  st0_previus_enable     = 1'b0; // 時効が飛んだので無効にする
                    st0_period_enable <= 1'b0; // 時効が飛んだので無効にする
                end

                // 誤差計算
                st0_error_phase <= t_phase'((current_time_correct - current_time_local));
            end
        end
    end


    // stage 1
    t_phase  st1_error_phase ;
    t_period st1_error_period;
    logic    st1_error_enable;
    logic    st1_valid       ;

    always_ff @ (posedge clk) begin
        if (reset) begin
            st1_error_phase  <= 'x;
            st1_error_period <= 'x;
            st1_error_enable <= 1'b0;
            st1_valid        <= 1'b0;
        end else begin
            if (st0_valid) begin
                st1_error_phase  <= st0_error_phase;
                st1_error_period <= t_period'((st0_period_correct - st0_period_local));
                st1_error_enable <= st0_period_enable; // 周期が有効なら誤差も有効
            end
            st1_valid <= st0_valid;
        end
    end

    // stage 2
    t_error st2_error_phase ;
    t_error st2_error_period;
    logic   st2_error_enable;
    logic   st2_valid       ;

    always_ff @ (posedge clk) begin
        if (reset) begin
            st2_error_phase  <= 'x;
            st2_error_period <= 'x;
            st2_error_enable <= 1'b0;
            st2_valid        <= 1'b0;
        end else begin
            // 今回周期補償する分を、位相誤差誤差から取り除く
            //          st2_error_phase  = PhaseToAdjust(st1_error_phase - st1_error_period as t_phase) >>> PHASE_LPF_GAIN;
            st2_error_phase  <= PhaseToAdjust(st1_error_phase) >>> PHASE_LPF_GAIN;
            st2_error_period <= PhaseToAdjust(st1_error_period);
            st2_error_enable <= st1_error_enable;
            st2_valid        <= st1_valid;
        end
    end

    // stage 3
    t_error st3_error_phase ;
    t_error st3_error_period;
    logic   st3_error_enable;
    logic   st3_valid       ;

    always_ff @ (posedge clk) begin
        if (reset) begin
            st3_error_phase  <= 'x;
            st3_error_period <= 'x;
            st3_error_enable <= 1'b0;
            st3_valid        <= 1'b0;
        end else begin
            st3_error_phase <= st2_error_phase;
            if (st2_error_phase < error_phase_min) begin
                st3_error_phase <= error_phase_min;
            end
            if (st2_error_phase > error_phase_max) begin
                st3_error_phase <= error_phase_max;
            end
            st3_error_period <= st2_error_period;
            st3_error_enable <= st2_error_enable & st2_valid;
            st3_valid        <= st2_valid;
        end
    end


    // stage 4
    t_error st4_adjust_phase ;
    t_error st4_adjust_period;
    t_error st4_change_phase ;
    t_error st4_change_period;
    logic   st4_enable       ;
    logic   st4_valid        ;

    t_error st3_corrected_error_period;
    //    assign st3_corrected_error_period = st3_error_period + st4_adjust_phase; // 前回の位相補正に含まれている分を、周期誤差から取り除く
    assign st3_corrected_error_period = st3_error_period; // 基準時間自体動かしたのでそんなものは不要

    always_ff @ (posedge clk) begin
        if (reset) begin
            st4_adjust_phase  <= '0;
            st4_adjust_period <= '0;
            st4_change_phase  <= 'x;
            st4_change_period <= 'x;
            st4_enable        <= 1'b0;
            st4_valid         <= 1'b0;
        end else begin
            if (st3_error_enable) begin
                if (st4_enable) begin
                    // ゲインを与えてLPFをかける
                    st4_adjust_phase  <=  st3_error_phase;
                    st4_adjust_period <= st4_adjust_period + (st3_corrected_error_period >>> PERIOD_LPF_GAIN);
                    st4_change_phase  <=  st3_error_phase;
                    st4_change_period <=  st3_corrected_error_period >>> PERIOD_LPF_GAIN;
                end else begin
                    // 初回設定
                    st4_adjust_phase  <= st3_error_phase;
                    st4_adjust_period <= st3_corrected_error_period;
                    st4_change_phase  <= st3_error_phase;
                    st4_change_period <= st3_corrected_error_period;
                    st4_enable        <= 1'b1;
                end
            end
            st4_valid <= st3_valid;
        end
    end

    // stage 5
    t_error st5_adjust_total;
    t_error st5_change_total;
    logic   st5_enable      ;
    logic   st5_valid       ;

    always_ff @ (posedge clk) begin
        if (reset) begin
            st5_adjust_total <= 'x;
            st5_change_total <= 'x;
            st5_enable       <= 1'b0;
            st5_valid        <= 1'b0;
        end else begin
            st5_adjust_total <= st4_adjust_period + st4_adjust_phase;
            st5_change_total <= st4_change_period + st4_change_phase;
            st5_enable       <= st4_enable;
            st5_valid        <= st4_valid;
        end
    end

    // stage 6
    t_error_u st6_count ; // 自クロックでの経過時刻計測
    t_error_u st6_adjust;
    logic     st6_sign  ;
    logic     st6_zero  ;
    logic     st6_enable;
    logic     st6_valid ;

    always_ff @ (posedge clk) begin
        if (reset) begin
            st6_sign   <= 'x;
            st6_zero   <= 'x;
            st6_adjust <= 'x;
            st6_count  <= 'x;
            st6_enable <= 1'b0;
            st6_valid  <= 1'b0;
        end else begin
            st6_count <= st6_count + (1'b1);
            if (st6_valid) begin
                st6_count <= '0;
            end

            if (st5_valid) begin
                st6_sign   <= st5_adjust_total < 0;
                st6_zero   <= st5_adjust_total == 0;
                st6_adjust <= ((st5_adjust_total < 0) ? (
                    t_error_u'((-st5_adjust_total))
                ) : (
                    t_error_u'(st5_adjust_total)
                ));
            end
            st6_enable <= st5_valid & st5_enable;
            st6_valid  <= st5_valid;
        end
    end

    always_ff @ (posedge clk) begin
        if (reset) begin
            next_change_total <= 'x;
            next_change_valid <= 1'b0;
        end else begin
            next_change_total <= AdjustToCalc(st5_change_total);
            next_change_valid <= st5_valid & st5_enable;
        end
    end


    // divider
    t_adjust  div_quotient ;
    t_error_u div_remainder;
    logic     div_valid    ;

    logic tmp_ready;
    jellyvl_divider_unsigned_multicycle #(
        .DIVIDEND_WIDTH (COUNTER_WIDTH + ERROR_Q),
        .DIVISOR_WIDTH  (ERROR_WIDTH + ERROR_Q  ),
        .QUOTIENT_WIDTH (ADJUST_WIDTH + ADJUST_Q)
    ) i_divider_unsigned_multicycle (
        .reset (reset),
        .clk   (clk  ),
        .cke   (1'b1 ),
        .
        s_dividend (t_count_q'(st6_count) << (ERROR_Q + ADJUST_Q)),
        .s_divisor  (st6_adjust                                  ),
        .s_valid    (st6_enable                                  ),
        .s_ready    (tmp_ready                                   ),
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
                if (st6_zero) begin
                    adj_param_zero   <= 1'b1;
                    adj_param_sign   <= 1'b0;
                    adj_param_period <= '0;
                    adj_param_valid  <= !adj_param_zero; // 変化があれば発行
                end else begin
                    adj_param_zero   <= st6_zero;
                    adj_param_sign   <= st6_sign;
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

    if (SIMULATION) begin :sim_monitor
        t_calc   sim_monitor_time_local            ;
        t_calc   sim_monitor_time_correct          ;
        t_calc   sim_monitor_period_local          ;
        t_calc   sim_monitor_period_correct        ;
        t_phase  sim_monitor_error_phase           ;
        t_period sim_monitor_error_period          ;
        real     sim_monitor_corrected_error_phase ;
        real     sim_monitor_corrected_error_period;
        real     sim_monitor_adjust_phase          ;
        real     sim_monitor_adjust_period         ;
        real     sim_monitor_adjust_total          ;

        always_ff @ (posedge clk) begin
            if (correct_valid) begin
                sim_monitor_time_local   <= current_time_local;
                sim_monitor_time_correct <= current_time_correct;
            end
            if (st3_valid) begin
                sim_monitor_corrected_error_phase  <= $itor(st3_error_phase) / $itor(2 ** ERROR_Q);
                sim_monitor_corrected_error_period <= $itor(st3_corrected_error_period) / $itor(2 ** ERROR_Q);
            end
        end

        assign sim_monitor_period_correct = st0_period_correct;
        assign sim_monitor_period_local   = st0_period_local;
        assign sim_monitor_error_phase    = st1_error_phase;
        assign sim_monitor_error_period   = st1_error_period;
        assign sim_monitor_adjust_phase   = $itor(st4_adjust_phase) / $itor(2 ** ERROR_Q);
        assign sim_monitor_adjust_period  = $itor(st4_adjust_period) / $itor(2 ** ERROR_Q);
        assign sim_monitor_adjust_total   = $itor(st5_adjust_total) / $itor(2 ** ERROR_Q);
    end
endmodule
