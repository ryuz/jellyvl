module jellyvl_etherneco_slave #(
    parameter int unsigned TIMER_WIDTH         = 64                             , // タイマのbit幅
    parameter int unsigned NUMERATOR           = 8                              , // クロック周期の分子
    parameter int unsigned DENOMINATOR         = 1                              , // クロック周期の分母
    parameter int unsigned ADJ_COUNTER_WIDTH   = 48                             , // 自クロックで経過時間カウンタのbit数
    parameter int unsigned ADJ_CALC_WIDTH      = 48                             , // タイマのうち計算に使う部分
    parameter int unsigned ADJ_ERROR_WIDTH     = 32                             , // 誤差計算時のbit幅
    parameter int unsigned ADJ_ERROR_Q         = 8                              , // 誤差計算時に追加する固定小数点数bit数
    parameter int unsigned ADJ_ADJUST_WIDTH    = ADJ_COUNTER_WIDTH + ADJ_ERROR_Q, // 補正周期のbit幅
    parameter int unsigned ADJ_ADJUST_Q        = ADJ_ERROR_Q                    , // 補正周期に追加する固定小数点数bit数
    parameter int unsigned ADJ_PERIOD_WIDTH    = ADJ_ERROR_WIDTH                , // 周期補正に使うbit数
    parameter int unsigned ADJ_PHASE_WIDTH     = ADJ_ERROR_WIDTH                , // 位相補正に使うbit数
    parameter int unsigned ADJ_PERIOD_LPF_GAIN = 4                              , // 周期補正のLPFの更新ゲイン(1/2^N)
    parameter int unsigned ADJ_PHASE_LPF_GAIN  = 4                               // 位相補正のLPFの更新ゲイン(1/2^N)
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

    // Outer loop
    logic          outer_rx_start ;
    logic          outer_rx_end   ;
    logic          outer_rx_error ;
    logic [16-1:0] outer_rx_length;
    logic [8-1:0]  outer_rx_type  ;
    logic [8-1:0]  outer_rx_node  ;

    logic          outer_payload_first;
    logic          outer_payload_last ;
    logic [16-1:0] outer_payload_pos  ;
    logic [8-1:0]  outer_payload_data ;
    logic          outer_payload_valid;
    logic [8-1:0]  outer_replace_data ;
    logic          outer_replace_valid;

    jellyvl_etherneco_packet_rx #(
        .DOWN_STREAM   (1'b0),
        .REPLACE_DELAY (0   )
    ) u_etherneco_packet_rx_outer (
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
        rx_start  (outer_rx_start ),
        .rx_end    (outer_rx_end   ),
        .rx_error  (outer_rx_error ),
        .rx_length (outer_rx_length),
        .rx_type   (outer_rx_type  ),
        .rx_node   (outer_rx_node  ),
        .
        payload_first (outer_payload_first),
        .payload_last  (outer_payload_last ),
        .payload_pos   (outer_payload_pos  ),
        .payload_data  (outer_payload_data ),
        .payload_valid (outer_payload_valid),
        .replace_data  (outer_replace_data ),
        .replace_valid (outer_replace_valid)
    );


    // Inner loop
    logic          inner_rx_start ;
    logic          inner_rx_end   ;
    logic          inner_rx_error ;
    logic [16-1:0] inner_rx_length;
    logic [8-1:0]  inner_rx_type  ;
    logic [8-1:0]  inner_rx_node  ;

    logic          inner_payload_first;
    logic          inner_payload_last ;
    logic [16-1:0] inner_payload_pos  ;
    logic [8-1:0]  inner_payload_data ;
    logic          inner_payload_valid;
    logic [8-1:0]  inner_replace_data ;
    logic          inner_replace_valid;

    jellyvl_etherneco_packet_rx #(
        .DOWN_STREAM   (1'b1),
        .REPLACE_DELAY (0   )
    ) u_etherneco_packet_rx_inner (
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
        rx_start  (inner_rx_start ),
        .rx_end    (inner_rx_end   ),
        .rx_error  (inner_rx_error ),
        .rx_length (inner_rx_length),
        .rx_type   (inner_rx_type  ),
        .rx_node   (inner_rx_node  ),
        .
        payload_first (inner_payload_first),
        .payload_last  (inner_payload_last ),
        .payload_pos   (inner_payload_pos  ),
        .payload_data  (inner_payload_data ),
        .payload_valid (inner_payload_valid),
        .replace_data  (inner_replace_data ),
        .replace_valid (inner_replace_valid)
    );



    // -------------------------------------
    // Functions
    // -------------------------------------

    jellyvl_etherneco_synctimer_slave #(
        .TIMER_WIDTH         (TIMER_WIDTH        ),
        .NUMERATOR           (NUMERATOR          ),
        .DENOMINATOR         (DENOMINATOR        ),
        .ADJ_COUNTER_WIDTH   (ADJ_COUNTER_WIDTH  ),
        .ADJ_CALC_WIDTH      (ADJ_CALC_WIDTH     ),
        .ADJ_ERROR_WIDTH     (ADJ_ERROR_WIDTH    ),
        .ADJ_ERROR_Q         (ADJ_ERROR_Q        ),
        .ADJ_ADJUST_WIDTH    (ADJ_ADJUST_WIDTH   ),
        .ADJ_ADJUST_Q        (ADJ_ADJUST_Q       ),
        .ADJ_PERIOD_WIDTH    (ADJ_PERIOD_WIDTH   ),
        .ADJ_PHASE_WIDTH     (ADJ_PHASE_WIDTH    ),
        .ADJ_PERIOD_LPF_GAIN (ADJ_PERIOD_LPF_GAIN),
        .ADJ_PHASE_LPF_GAIN  (ADJ_PHASE_LPF_GAIN )
    ) u_etherneco_synctimer_slave (
        .reset (reset),
        .clk   (clk  ),
        .
        current_time (current_time),
        .
        cmd_rx_start  (outer_rx_start     ),
        .cmd_rx_end    (outer_rx_end       ),
        .cmd_rx_error  (outer_rx_error     ),
        .cmd_rx_length (outer_rx_length    ),
        .cmd_rx_type   (outer_rx_type      ),
        .cmd_rx_node   (outer_rx_node      ),
        .s_cmd_first   (outer_payload_first),
        .s_cmd_last    (outer_payload_last ),
        .s_cmd_pos     (outer_payload_pos  ),
        .s_cmd_data    (outer_payload_data ),
        .s_cmd_valid   (outer_payload_valid),
        .m_cmd_data    (outer_replace_data ),
        .m_cmd_valid   (outer_replace_valid),
        .
        res_rx_start  (inner_rx_start     ),
        .res_rx_end    (inner_rx_end       ),
        .res_rx_error  (inner_rx_error     ),
        .res_rx_length (inner_rx_length    ),
        .res_rx_type   (inner_rx_type      ),
        .res_rx_node   (inner_rx_node      ),
        .s_res_first   (inner_payload_first),
        .s_res_last    (inner_payload_last ),
        .s_res_pos     (inner_payload_pos  ),
        .s_res_data    (inner_payload_data ),
        .s_res_valid   (inner_payload_valid),
        .m_res_data    (inner_replace_data ),
        .m_res_valid   (inner_replace_valid)
    );

endmodule
