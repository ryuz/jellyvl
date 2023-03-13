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


    // -------------------------------------
    //  Outer loop (request)
    // -------------------------------------

    // 上流からの受信
    logic         outer_rx_first;
    logic         outer_rx_last ;
    logic [8-1:0] outer_rx_data ;
    logic         outer_rx_valid;

    logic          outer_rx_start ;
    logic          outer_rx_end   ;
    logic          outer_rx_error ;
    logic [16-1:0] outer_rx_length;

    jellyvl_etherneco_rx u_etherneco_rx_outer (
        .reset (reset),
        .clk   (clk  ),
        .
        rx_start  (outer_rx_start ),
        .rx_end    (outer_rx_end   ),
        .rx_error  (outer_rx_error ),
        .rx_length (outer_rx_length),
        .
        s_first (s_up_rx_first),
        .s_last  (s_up_rx_last ),
        .s_data  (s_up_rx_data ),
        .s_valid (s_up_rx_valid),
        .
        m_first (outer_rx_first),
        .m_last  (outer_rx_last ),
        .m_data  (outer_rx_data ),
        .m_valid (outer_rx_valid)
    );


    // 同期タイマ(スレーブ)
    logic         outer_tx_first;
    logic         outer_tx_last ;
    logic [8-1:0] outer_tx_data ;
    logic         outer_tx_valid;
    logic         outer_tx_ready;

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
        rx_start (outer_rx_start),
        .rx_error (outer_rx_error),
        .rx_end   (outer_rx_end  ),
        .
        s_first (outer_rx_first),
        .s_last  (outer_rx_last ),
        .s_data  (outer_rx_data ),
        .s_valid (outer_rx_valid),
        .
        m_first (outer_tx_first),
        .m_last  (outer_tx_last ),
        .m_data  (outer_tx_data ),
        .m_valid (outer_tx_valid)
    );

    // さらに下流に流す
    jellyvl_etherneco_tx #(
        .FIFO_PTR_WIDTH (5)
    ) u_etherneco_tx_outer (
        .reset (reset),
        .clk   (clk  ),
        .
        tx_start  (outer_rx_start ),
        .tx_length (outer_rx_length),
        .
        tx_cancel (outer_rx_error),
        .
        s_last  (outer_tx_last ),
        .s_data  (outer_tx_data ),
        .s_valid (outer_tx_valid),
        .s_ready (outer_tx_ready),
        .
        m_first (m_down_tx_first),
        .m_last  (m_down_tx_last ),
        .m_data  (m_down_tx_data ),
        .m_valid (m_down_tx_valid),
        .m_ready (m_down_tx_ready)
    );



    // -------------------------------------
    //  Inner loop (response)
    // -------------------------------------

endmodule
