module jellyvl_etherneco_slave #(
    parameter int unsigned TIMER_WIDTH       = 64                             , // タイマのbit幅
    parameter int unsigned NUMERATOR         = 8                              , // クロック周期の分子
    parameter int unsigned DENOMINATOR       = 1                              , // クロック周期の分母
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

    input  logic         s_up_rx_first,
    input  logic         s_up_rx_last ,
    input  logic [8-1:0] s_up_rx_data ,
    input  logic         s_up_rx_valid,
    output logic         m_up_tx_first,
    output logic         m_up_tx_last ,
    output logic [8-1:0] m_up_tx_data ,
    output logic         m_up_tx_valid,
    input  logic         m_up_tx_ready,

    input  logic         s_down_rx_first,
    input  logic         s_down_rx_last ,
    input  logic [8-1:0] s_down_rx_data ,
    input  logic         s_down_rx_valid,
    output logic         m_down_tx_first,
    output logic         m_down_tx_last ,
    output logic [8-1:0] m_down_tx_data ,
    output logic         m_down_tx_valid,
    input  logic         m_down_tx_ready
);


    // 上流からの受信
    logic         up_rx_first;
    logic         up_rx_last ;
    logic [8-1:0] up_rx_data ;
    logic         up_rx_valid;

    logic up_rx_start;
    logic up_rx_end  ;
    logic up_rx_error;

    jellyvl_etherneco_rx u_etherneco_rx_up (
        .reset (reset),
        .clk   (clk  ),
        .
        rx_start (up_rx_start),
        .rx_end   (up_rx_end  ),
        .rx_error (up_rx_error),
        .
        s_first (s_up_rx_first),
        .s_last  (s_up_rx_last ),
        .s_data  (s_up_rx_data ),
        .s_valid (s_up_rx_valid),
        .
        m_first (up_rx_first),
        .m_last  (up_rx_last ),
        .m_data  (up_rx_data ),
        .m_valid (up_rx_valid)
    );


    // 同期タイマ(スレーブ)
    logic         down_tx_first;
    logic         down_tx_last ;
    logic [8-1:0] down_tx_data ;
    logic         down_tx_valid;

    jellyvl_etherneco_synctimer_slave #(
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
    ) u_etherneco_synctimer_slave (
        .reset (reset),
        .clk   (clk  ),
        .
        current_time (current_time),
        .
        rx_start (up_rx_start),
        .rx_error (up_rx_error),
        .rx_end   (up_rx_end  ),
        .
        s_first (up_rx_first),
        .s_last  (up_rx_last ),
        .s_data  (up_rx_data ),
        .s_valid (up_rx_valid),
        .
        m_first (down_tx_first),
        .m_last  (down_tx_last ),
        .m_data  (down_tx_data ),
        .m_valid (down_tx_valid)
    );

endmodule
