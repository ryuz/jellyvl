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


    // ---------------------------------
    //  Ring bus
    // ---------------------------------

    // upstream
    logic          up_rx_start ;
    logic          up_rx_end   ;
    logic          up_rx_error ;
    logic [16-1:0] up_rx_length;
    logic [8-1:0]  up_rx_type  ;
    logic [8-1:0]  up_rx_node  ;

    logic          up_payload_first;
    logic          up_payload_last ;
    logic [16-1:0] up_payload_pos  ;
    logic [8-1:0]  up_payload_data ;
    logic          up_payload_valid;
    logic [8-1:0]  up_replace_data ;
    logic          up_replace_valid;

    jellyvl_etherneco_packet_rx #(
        .DOWN_STREAM   (1'b0),
        .REPLACE_DELAY (1   )
    ) u_etherneco_packet_up (
        .reset (reset),
        .clk   (clk  ),
        .
        s_rx_first (s_up_rx_first),
        .s_rx_last  (s_up_rx_last ),
        .s_rx_data  (s_up_rx_data ),
        .s_rx_valid (s_up_rx_valid),
        .
        m_tx_first (m_down_tx_first),
        .m_tx_last  (m_down_tx_last ),
        .m_tx_data  (m_down_tx_data ),
        .m_tx_valid (m_down_tx_valid),
        .
        rx_start  (up_rx_start ),
        .rx_end    (up_rx_end   ),
        .rx_error  (up_rx_error ),
        .rx_length (up_rx_length),
        .rx_type   (up_rx_type  ),
        .rx_node   (up_rx_node  ),
        .
        payload_first (up_payload_first),
        .payload_last  (up_payload_last ),
        .payload_pos   (up_payload_pos  ),
        .payload_data  (up_payload_data ),
        .payload_valid (up_payload_valid),
        .replace_data  (up_replace_data ),
        .replace_valid (up_replace_valid)
    );


    // downstream
    logic          down_rx_start ;
    logic          down_rx_end   ;
    logic          down_rx_error ;
    logic [16-1:0] down_rx_length;
    logic [8-1:0]  down_rx_type  ;
    logic [8-1:0]  down_rx_node  ;

    logic          down_payload_first;
    logic          down_payload_last ;
    logic [16-1:0] down_payload_pos  ;
    logic [8-1:0]  down_payload_data ;
    logic          down_payload_valid;
    logic [8-1:0]  down_replace_data ;
    logic          down_replace_valid;

    jellyvl_etherneco_packet_rx #(
        .DOWN_STREAM   (1'b1),
        .REPLACE_DELAY (1   )
    ) u_etherneco_packet_down (
        .reset (reset),
        .clk   (clk  ),
        .
        s_rx_first (s_down_rx_first),
        .s_rx_last  (s_down_rx_last ),
        .s_rx_data  (s_down_rx_data ),
        .s_rx_valid (s_down_rx_valid),
        .
        m_tx_first (m_up_tx_first),
        .m_tx_last  (m_up_tx_last ),
        .m_tx_data  (m_up_tx_data ),
        .m_tx_valid (m_up_tx_valid),
        .
        rx_start  (down_rx_start ),
        .rx_end    (down_rx_end   ),
        .rx_error  (down_rx_error ),
        .rx_length (down_rx_length),
        .rx_type   (down_rx_type  ),
        .rx_node   (down_rx_node  ),
        .
        payload_first (down_payload_first),
        .payload_last  (down_payload_last ),
        .payload_pos   (down_payload_pos  ),
        .payload_data  (down_payload_data ),
        .payload_valid (down_payload_valid),
        .replace_data  (down_replace_data ),
        .replace_valid (down_replace_valid)
    );



    // -------------------------------------
    // Functions
    // -------------------------------------

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
        up_rx_start  (up_rx_start     ),
        .up_rx_end    (up_rx_end       ),
        .up_rx_error  (up_rx_error     ),
        .up_rx_length (up_rx_length    ),
        .up_rx_type   (up_rx_type      ),
        .up_rx_node   (up_rx_node      ),
        .s_up_first   (up_payload_first),
        .s_up_last    (up_payload_last ),
        .s_up_pos     (up_payload_pos  ),
        .s_up_data    (up_payload_data ),
        .s_up_valid   (up_payload_valid),
        .m_up_data    (up_replace_data ),
        .m_up_valid   (up_replace_valid),
        .
        down_rx_start  (down_rx_start     ),
        .down_rx_end    (down_rx_end       ),
        .down_rx_error  (down_rx_error     ),
        .down_rx_length (down_rx_length    ),
        .down_rx_type   (down_rx_type      ),
        .down_rx_node   (down_rx_node      ),
        .s_down_first   (down_payload_first),
        .s_down_last    (down_payload_last ),
        .s_down_pos     (down_payload_pos  ),
        .s_down_data    (down_payload_data ),
        .s_down_valid   (down_payload_valid),
        .m_down_data    (down_replace_data ),
        .m_down_valid   (down_replace_valid)
    );

endmodule
