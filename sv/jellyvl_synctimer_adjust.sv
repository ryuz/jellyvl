
// 調整機構
module jellyvl_synctimer_adjust #(
    parameter int unsigned TIMER_WIDTH     = 64                     , // タイマのbit幅
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
    parameter bit          DEBUG           = 1'b0                   ,
    parameter bit          SIMULATION      = 1'b1               
) (
    input logic reset,
    input logic clk  ,

    input logic signed [PHASE_WIDTH-1:0] param_phase_min,
    input logic signed [PHASE_WIDTH-1:0] param_phase_max,

    input logic [TIMER_WIDTH-1:0] local_time,

    input logic                   correct_override,
    input logic [TIMER_WIDTH-1:0] correct_time    ,
    input logic                   correct_valid   ,

    output logic adjust_sign ,
    output logic adjust_valid,
    input  logic adjust_ready

);

    // type
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


    // input
    t_calc current_local_time  ;
    t_calc current_correct_time;
    assign current_local_time   = t_calc'(local_time);
    assign current_correct_time = t_calc'(correct_time);


    // stage 0
    t_calc  st0_previus_local_time  ;
    t_calc  st0_previus_correct_time;
    t_calc  st0_local_period        ;
    t_calc  st0_correct_period      ;
    logic   st0_first               ;
    t_phase st0_phase_error         ;
    logic   st0_valid               ;
    logic   st0_counter_trig        ;

    always_ff @ (posedge clk) begin
        if (reset) begin
            st0_counter_trig         <= 1'bx;
            st0_previus_local_time   <= 'x;
            st0_previus_correct_time <= 'x;
            st0_local_period         <= 'x;
            st0_correct_period       <= 'x;
            st0_first                <= 1'b1;
            st0_phase_error          <= 'x;
            st0_valid                <= 1'b0;
        end else begin
            st0_counter_trig <= correct_valid;
            st0_valid        <= 1'b0;
            if (correct_valid) begin
                st0_previus_local_time   <= current_local_time;
                st0_previus_correct_time <= current_correct_time;
                st0_local_period         <= current_local_time - st0_previus_local_time;
                st0_correct_period       <= current_correct_time - st0_previus_correct_time;

                st0_first       <= 1'b0;
                st0_phase_error <= t_phase'((current_correct_time - current_local_time));
                if (!(st0_first || correct_override)) begin
                    st0_valid <= 1'b1;
                end
            end
        end
    end


    // stage 1
    logic   st1_first       ;
    t_error st1_phase_error ;
    t_error st1_period_error;
    logic   st1_valid       ;
    logic   st1_counter_trig;

    always_ff @ (posedge clk) begin
        if (reset) begin
            st1_counter_trig <= 1'bx;
            st1_first        <= 1'b1;
            st1_phase_error  <= '0;
            st1_period_error <= 'x;
            st1_valid        <= 1'b0;
        end else begin
            st1_counter_trig <= st0_counter_trig;
            if (st0_valid) begin
                st1_first       <= 1'b0;
                st1_phase_error <= PhaseToAdjust(st0_phase_error);
                if (st0_phase_error <= param_phase_min) begin
                    st1_phase_error <= PhaseToAdjust(param_phase_min);
                end
                if (st0_phase_error >= param_phase_max) begin
                    st1_phase_error <= PhaseToAdjust(param_phase_max);
                end
                st1_period_error <= PeriodToAdjust(t_period'((st0_correct_period - st0_local_period)));
            end
            st1_valid <= st0_valid && !st1_first;

            if (correct_valid && correct_override) begin
                st1_first <= 1'b1;
            end

        end
    end
    t_error st1_phase_error_int ;
    t_error st1_period_error_int;
    assign st1_phase_error_int  = st1_phase_error >>> ERROR_Q;
    assign st1_period_error_int = st1_period_error >>> ERROR_Q;


    // stage 2
    logic   st2_first        ;
    t_error st2_phase_adjust ;
    t_error st2_period_adjust;
    logic   st2_valid        ;
    logic   st2_counter_trig ;

    t_error st1_period_error_t;
    assign st1_period_error_t = st1_period_error + st2_phase_adjust; // st1_local_period に前回位相補正が含まれているのでその分相殺

    always_ff @ (posedge clk) begin
        if (reset) begin
            st2_counter_trig  <= 1'bx;
            st2_first         <= 1'b1;
            st2_phase_adjust  <= '0;
            st2_period_adjust <= '0;
            st2_valid         <= 1'b0;
        end else begin
            st2_counter_trig <= st1_counter_trig;
            if (st1_valid) begin
                st2_first <= 1'b0;

                // ゲインを与えてLPFをかける
                st2_phase_adjust <= st1_phase_error >>> PHASE_LPF_GAIN;

                // ゲインを与えてLPFをかける
                st2_period_adjust <= st2_period_adjust + (st1_period_error_t >>> PERIOD_LPF_GAIN);
            end
            st2_valid <= st1_valid;

            if (correct_valid && correct_override) begin
                st2_first <= 1'b1;
            end
        end
    end

    // stage 3
    t_error st3_adjust      ;
    logic   st3_valid       ;
    logic   st3_counter_trig;

    always_ff @ (posedge clk) begin
        if (reset) begin
            st3_counter_trig <= 1'bx;
            st3_adjust       <= 'x;
            st3_valid        <= 1'b0;
        end else begin
            st3_counter_trig <= st2_counter_trig;
            st3_adjust       <= st2_period_adjust + st2_phase_adjust;
            st3_valid        <= st2_valid;
        end
    end

    // stage 3
    logic     st4_counter_trig;
    t_error_u st4_count       ; // 自クロックでの経過時刻計測
    t_error_u st4_adjust      ;
    logic     st4_sign        ;
    logic     st4_zero        ;
    logic     st4_valid       ;

    always_ff @ (posedge clk) begin
        if (reset) begin
            st4_sign         <= 'x;
            st4_zero         <= 'x;
            st4_adjust       <= 'x;
            st4_count        <= 'x;
            st4_valid        <= 1'b0;
            st4_counter_trig <= 1'b0;
        end else begin
            st4_count <= st4_count + (1'b1);
            if (st4_counter_trig) begin
                st4_count <= '0;
            end
            st4_counter_trig <= st3_counter_trig;

            if (st3_valid) begin
                st4_sign   <= st3_adjust < 0;
                st4_zero   <= st3_adjust == 0;
                st4_adjust <= ((st3_adjust < 0) ? (
                    t_error_u'((-st3_adjust))
                ) : (
                    t_error_u'(st3_adjust)
                ));
            end
            st4_valid <= st3_valid;
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
        s_dividend (t_count_q'(st4_count) << (ERROR_Q + ADJUST_Q)),
        .s_divisor  (st4_adjust                                  ),
        .s_valid    (st4_valid                                   ),
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
                if (st4_zero) begin
                    adj_param_zero   <= 1'b1;
                    adj_param_sign   <= 1'b0;
                    adj_param_period <= '0;
                    adj_param_valid  <= !adj_param_zero; // 変化があれば発行
                end else begin
                    adj_param_zero   <= st4_zero;
                    adj_param_sign   <= st4_sign;
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

    if (SIMULATION) begin :monitor
        t_calc monitor_local_time    ;
        t_calc monitor_correct_time  ;
        t_calc monitor_local_period  ;
        t_calc monitor_correct_period;
        real   monitor_phase_error   ;
        real   monitor_period_error  ;
        real   monitor_period_error_t;
        real   monitor_phase_adjust  ;
        real   monitor_period_adjust ;
        real   monitor_total_adjust  ;

        always_ff @ (posedge clk) begin
            if (correct_valid) begin
                monitor_local_time   <= current_local_time;
                monitor_correct_time <= current_correct_time;
            end
            if (st1_valid) begin
                monitor_period_error_t <= $itor(st1_period_error_t) / $itor(2 ** ERROR_Q);
            end
        end

        assign monitor_correct_period = st0_correct_period;
        assign monitor_local_period   = st0_local_period;
        assign monitor_phase_error    = $itor(st1_phase_error) / $itor(2 ** ERROR_Q);
        assign monitor_period_error   = $itor(st1_period_error) / $itor(2 ** ERROR_Q);
        assign monitor_phase_adjust   = $itor(st2_phase_adjust) / $itor(2 ** ERROR_Q);
        assign monitor_period_adjust  = $itor(st2_period_adjust) / $itor(2 ** ERROR_Q);
        assign monitor_total_adjust   = $itor(st3_adjust) / $itor(2 ** ERROR_Q);
    end
endmodule
