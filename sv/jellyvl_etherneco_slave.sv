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

    logic          outer_rx_start ;
    logic          outer_rx_end   ;
    logic          outer_rx_error ;
    logic [16-1:0] outer_rx_length;
    logic [8-1:0]  outer_rx_type  ;
    logic [8-1:0]  outer_rx_node  ;

    logic         outer_rx_first;
    logic         outer_rx_last ;
    logic [8-1:0] outer_rx_data ;
    logic         outer_rx_valid;

    logic         outer_tx_first;
    logic         outer_tx_last ;
    logic [8-1:0] outer_tx_data ;
    logic         outer_tx_valid;
    logic         outer_tx_ready;

    // 上流からのリクエスト受信
    jellyvl_etherneco_packet_rx u_etherneco_packet_rx_outer (
        .reset (reset),
        .clk   (clk  ),
        .
        rx_start  (outer_rx_start ),
        .rx_end    (outer_rx_end   ),
        .rx_error  (outer_rx_error ),
        .rx_length (outer_rx_length),
        .rx_type   (outer_rx_type  ),
        .rx_node   (outer_rx_node  ),
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


    // さらに下流にリクエストを流す
    jellyvl_etherneco_packet_tx #(
        .FIFO_PTR_WIDTH (5)
    ) u_etherneco_packet_tx_outer (
        .reset (reset),
        .clk   (clk  ),
        .
        tx_start  (outer_rx_start      ),
        .tx_length (outer_rx_length     ),
        .tx_type   (outer_rx_type       ),
        .tx_node   (outer_rx_node + 1'b1),
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

    logic          inner_rx_start ;
    logic          inner_rx_end   ;
    logic          inner_rx_error ;
    logic [16-1:0] inner_rx_length;
    logic [8-1:0]  inner_rx_type  ;
    logic [8-1:0]  inner_rx_node  ;

    logic         inner_rx_first;
    logic         inner_rx_last ;
    logic [8-1:0] inner_rx_data ;
    logic         inner_rx_valid;

    logic         inner_tx_first;
    logic         inner_tx_last ;
    logic [8-1:0] inner_tx_data ;
    logic         inner_tx_valid;
    logic         inner_tx_ready;


    // 下流からのレスポンス受信
    jellyvl_etherneco_packet_rx u_etherneco_packet_rx_inner (
        .reset (reset),
        .clk   (clk  ),
        .
        rx_start  (inner_rx_start ),
        .rx_end    (inner_rx_end   ),
        .rx_error  (inner_rx_error ),
        .rx_length (inner_rx_length),
        .rx_type   (inner_rx_type  ),
        .rx_node   (inner_rx_node  ),
        .
        s_first (s_down_rx_first),
        .s_last  (s_down_rx_last ),
        .s_data  (s_down_rx_data ),
        .s_valid (s_down_rx_valid),
        .
        m_first (inner_rx_first),
        .m_last  (inner_rx_last ),
        .m_data  (inner_rx_data ),
        .m_valid (inner_rx_valid)
    );

    // 上流へレスポンス応答
    jellyvl_etherneco_packet_tx #(
        .FIFO_PTR_WIDTH (5)
    ) u_etherneco_packet_tx_inner (
        .reset (reset),
        .clk   (clk  ),
        .
        tx_start  (outer_rx_start      ),
        .tx_length (outer_rx_length     ),
        .tx_type   (outer_rx_type       ),
        .tx_node   (outer_rx_node - 1'b1),
        .
        tx_cancel (outer_rx_error),
        .
        s_last  (inner_tx_last ),
        .s_data  (inner_tx_data ),
        .s_valid (inner_tx_valid),
        .s_ready (inner_tx_ready),
        .
        m_first (m_up_tx_first),
        .m_last  (m_up_tx_last ),
        .m_data  (m_up_tx_data ),
        .m_valid (m_up_tx_valid),
        .m_ready (m_up_tx_ready)
    );



    // -------------------------------------
    // Functions
    // -------------------------------------


    // 同期タイマ(スレーブ)

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
        node_id (outer_rx_node),
        .
        outer_rx_start (outer_rx_start),
        .outer_rx_error (outer_rx_error),
        .outer_rx_end   (outer_rx_end  ),
        .
        s_outer_rx_first (outer_rx_first),
        .s_outer_rx_last  (outer_rx_last ),
        .s_outer_rx_data  (outer_rx_data ),
        .s_outer_rx_valid (outer_rx_valid),
        .
        m_outer_tx_first (outer_tx_first),
        .m_outer_tx_last  (outer_tx_last ),
        .m_outer_tx_data  (outer_tx_data ),
        .m_outer_tx_valid (outer_tx_valid),
        .
        inner_rx_start (inner_rx_start),
        .inner_rx_error (inner_rx_error),
        .inner_rx_end   (inner_rx_end  ),
        .
        s_inner_rx_first (inner_rx_first),
        .s_inner_rx_last  (inner_rx_last ),
        .s_inner_rx_data  (inner_rx_data ),
        .s_inner_rx_valid (inner_rx_valid),
        .
        m_inner_tx_first (inner_tx_first),
        .m_inner_tx_last  (inner_tx_last ),
        .m_inner_tx_data  (inner_tx_data ),
        .m_inner_tx_valid (inner_tx_valid)

    );

endmodule
