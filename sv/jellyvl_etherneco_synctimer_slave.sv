module jellyvl_etherneco_synctimer_slave #(
    parameter int unsigned TIMER_WIDTH       = 64                             , // タイマのbit幅
    parameter int unsigned NUMERATOR         = 10                             , // クロック周期の分子
    parameter int unsigned DENOMINATOR       = 3                              , // クロック周期の分母
    parameter int unsigned ADJ_COUNTER_WIDTH = 32                             , // 自クロックで経過時間カウンタのbit数
    parameter int unsigned ADJ_CALC_WIDTH    = 32                             , // タイマのうち計算に使う部分
    parameter int unsigned ADJ_ERROR_WIDTH   = 32                             , // 誤差計算時のbit幅
    parameter int unsigned ADJ_ERROR_Q       = 8                              , // 誤差計算時に追加する固定小数点数bit数
    parameter int unsigned ADJ_ADJUST_WIDTH  = ADJ_COUNTER_WIDTH + ADJ_ERROR_Q, // 補正周期のbit幅
    parameter int unsigned ADJ_ADJUST_Q      = ADJ_ERROR_Q                    , // 補正周期に追加する固定小数点数bit数
    parameter int unsigned ADJ_PERIOD_WIDTH  = ADJ_ERROR_WIDTH                , // 周期補正に使うbit数
    parameter int unsigned ADJ_PHASE_WIDTH   = ADJ_ERROR_WIDTH                 // 位相補正に使うbit数
) (
    input logic reset,
    input logic clk  ,

    output logic [TIMER_WIDTH-1:0] current_time,

    input logic [8-1:0] node_id,

    input logic outer_rx_start,
    input logic outer_rx_error,
    input logic outer_rx_end  ,

    input logic         s_outer_rx_first,
    input logic         s_outer_rx_last ,
    input logic [8-1:0] s_outer_rx_data ,
    input logic         s_outer_rx_valid,

    output logic         m_outer_tx_first,
    output logic         m_outer_tx_last ,
    output logic [8-1:0] m_outer_tx_data ,
    output logic         m_outer_tx_valid,

    input logic inner_rx_start,
    input logic inner_rx_error,
    input logic inner_rx_end  ,

    input logic         s_inner_rx_first,
    input logic         s_inner_rx_last ,
    input logic [8-1:0] s_inner_rx_data ,
    input logic         s_inner_rx_valid,

    output logic         m_inner_tx_first,
    output logic         m_inner_tx_last ,
    output logic [8-1:0] m_inner_tx_data ,
    output logic         m_inner_tx_valid

);

    // -------------------------
    //  Timer
    // -------------------------

    localparam type t_adj_phase = logic signed [ADJ_PHASE_WIDTH-1:0];
    localparam type t_time      = logic [TIMER_WIDTH-1:0];

    logic  correct_override;
    t_time correct_time    ;
    logic  correct_valid   ;

    jellyvl_synctimer_core #(
        .TIMER_WIDTH       (TIMER_WIDTH      ),
        .NUMERATOR         (NUMERATOR        ),
        .DENOMINATOR       (DENOMINATOR      ),
        .ADJ_COUNTER_WIDTH (ADJ_COUNTER_WIDTH),
        .ADJ_CALC_WIDTH    (ADJ_CALC_WIDTH   ),
        .ADJ_ERROR_WIDTH   (ADJ_ERROR_WIDTH  ),
        .ADJ_ERROR_Q       (ADJ_ERROR_Q      ),
        .ADJ_ADJUST_WIDTH  (ADJ_ADJUST_WIDTH ),
        .ADJ_ADJUST_Q      (ADJ_ADJUST_Q     ),
        .ADJ_PERIOD_WIDTH  (ADJ_PERIOD_WIDTH ),
        .ADJ_PHASE_WIDTH   (ADJ_PHASE_WIDTH  )
    ) u_synctimer_core (
        .reset (reset),
        .clk   (clk  ),
        .
        adj_param_phase_min (t_adj_phase'(-10)),
        .adj_param_phase_max (t_adj_phase'(+10)),
        .
        set_time  ('0  ),
        .set_valid (1'b0),
        .
        current_time (current_time),
        .
        correct_override (correct_override),
        .correct_time     (correct_time    ),
        .correct_valid    (correct_valid   )
    );

    // -------------------------
    //  Outer ring (Resquest)
    // -------------------------

    jellyvl_etherneco_synctimer_slave_request u_etherneco_synctimer_slave_request (
        .reset            (reset           ),
        .clk              (clk             ),
        .correct_override (correct_override),
        .correct_time     (correct_time    ),
        .correct_valid    (correct_valid   ),
        .
        rx_start (outer_rx_start),
        .rx_error (outer_rx_error),
        .rx_end   (outer_rx_end  ),
        .
        s_first (s_outer_rx_first),
        .s_last  (s_outer_rx_last ),
        .s_data  (s_outer_rx_data ),
        .s_valid (s_outer_rx_valid),
        .
        m_first (m_outer_tx_first),
        .m_last  (m_outer_tx_last ),
        .m_data  (m_outer_tx_data ),
        .m_valid (m_outer_tx_valid)
    );


    // -------------------------
    // Inner Ring (Response)
    // -------------------------

    localparam type t_delay = logic [32-1:0];

    t_delay start_time;
    t_delay delay_time;
    always_ff @ (posedge clk) begin
        if (outer_rx_end) begin
            start_time <= t_delay'(current_time);
        end
        if (inner_rx_start) begin
            delay_time <= t_delay'(current_time) - start_time;
        end
    end

    jellyvl_etherneco_synctimer_slave_response u_etherneco_synctimer_slave_response (
        .reset (reset),
        .clk   (clk  ),
        .
        node_id    (node_id   ),
        .delay_time (start_time),
        .
        rx_start (outer_rx_start),
        .rx_error (outer_rx_error),
        .rx_end   (outer_rx_end  ),
        .
        s_first (s_outer_rx_first),
        .s_last  (s_outer_rx_last ),
        .s_data  (s_outer_rx_data ),
        .s_valid (s_outer_rx_valid),
        .
        m_first (m_outer_tx_first),
        .m_last  (m_outer_tx_last ),
        .m_data  (m_outer_tx_data ),
        .m_valid (m_outer_tx_valid)
    );

endmodule
