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
        s_first (s_up_rx_first),
        .s_last  (s_up_rx_last ),
        .s_data  (s_up_rx_data ),
        .s_valid (s_up_rx_valid),
        .
        m_first (m_down_tx_first),
        .m_last  (m_down_tx_last ),
        .m_data  (m_down_tx_data ),
        .m_valid (m_down_tx_valid),
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
        s_first (s_down_rx_first),
        .s_last  (s_down_rx_last ),
        .s_data  (s_down_rx_data ),
        .s_valid (s_down_rx_valid),
        .
        m_first (m_up_tx_first),
        .m_last  (m_up_tx_last ),
        .m_data  (m_up_tx_data ),
        .m_valid (m_up_tx_valid),
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





    /*
    var outer_rx_start : logic    ;
    var outer_rx_end   : logic    ;
    var outer_rx_error : logic    ;
    var outer_rx_length: logic<16>;
    var outer_rx_type  : logic<8> ;
    var outer_rx_node  : logic<8> ;

    var outer_rx_first: logic   ;
    var outer_rx_last : logic   ;
    var outer_rx_data : logic<8>;
    var outer_rx_valid: logic   ;

    var outer_tx_first: logic   ;
    var outer_tx_last : logic   ;
    var outer_tx_data : logic<8>;
    var outer_tx_valid: logic   ;
    var outer_tx_ready: logic   ;

    // 上流からのリクエスト受信
    inst u_etherneco_packet_rx_outer: etherneco_packet_rx_old (
        reset: reset,
        clk  : clk  ,

        rx_start : outer_rx_start ,
        rx_end   : outer_rx_end   ,
        rx_error : outer_rx_error ,
        rx_length: outer_rx_length,
        rx_type  : outer_rx_type  ,
        rx_node  : outer_rx_node  ,

        s_first: s_up_rx_first,
        s_last : s_up_rx_last ,
        s_data : s_up_rx_data ,
        s_valid: s_up_rx_valid,

        m_first: outer_rx_first,
        m_last : outer_rx_last ,
        m_data : outer_rx_data ,
        m_valid: outer_rx_valid,
    );


    // さらに下流にリクエストを流す
    inst u_etherneco_packet_tx_outer: etherneco_packet_tx #(
        FIFO_PTR_WIDTH: 5,
    ) (
        reset: reset,
        clk  : clk  ,

        tx_start : outer_rx_start      ,
        tx_length: outer_rx_length     ,
        tx_type  : outer_rx_type       ,
        tx_node  : outer_rx_node + 1'b1,

        tx_cancel: outer_rx_error,

        s_last : outer_tx_last ,
        s_data : outer_tx_data ,
        s_valid: outer_tx_valid,
        s_ready: outer_tx_ready,

        m_first: m_down_tx_first,
        m_last : m_down_tx_last ,
        m_data : m_down_tx_data ,
        m_valid: m_down_tx_valid,
        m_ready: m_down_tx_ready,
    );
    */


    // -------------------------------------
    //  Inner loop (response)
    // -------------------------------------
    /*

    var inner_rx_start : logic    ;
    var inner_rx_end   : logic    ;
    var inner_rx_error : logic    ;
    var inner_rx_length: logic<16>;
    var inner_rx_type  : logic<8> ;
    var inner_rx_node  : logic<8> ;

    var inner_rx_first: logic   ;
    var inner_rx_last : logic   ;
    var inner_rx_data : logic<8>;
    var inner_rx_valid: logic   ;

    //    var inner_tx_first: logic   ;
    var inner_tx_last : logic   ;
    var inner_tx_data : logic<8>;
    var inner_tx_valid: logic   ;
    var inner_tx_ready: logic   ;


    // 下流からのレスポンス受信
    inst u_etherneco_packet_rx_inner: etherneco_packet_rx_old (
        reset: reset,
        clk  : clk  ,

        rx_start : inner_rx_start ,
        rx_end   : inner_rx_end   ,
        rx_error : inner_rx_error ,
        rx_length: inner_rx_length,
        rx_type  : inner_rx_type  ,
        rx_node  : inner_rx_node  ,

        s_first: s_down_rx_first,
        s_last : s_down_rx_last ,
        s_data : s_down_rx_data ,
        s_valid: s_down_rx_valid,

        m_first: inner_rx_first,
        m_last : inner_rx_last ,
        m_data : inner_rx_data ,
        m_valid: inner_rx_valid,
    );

    // 上流へレスポンス応答
    inst u_etherneco_packet_tx_inner: etherneco_packet_tx #(
        FIFO_PTR_WIDTH: 5,
    ) (
        reset: reset,
        clk  : clk  ,

        tx_start : outer_rx_start      ,
        tx_length: outer_rx_length     ,
        tx_type  : outer_rx_type       ,
        tx_node  : outer_rx_node - 1'b1,

        tx_cancel: outer_rx_error,

        s_last : inner_tx_last ,
        s_data : inner_tx_data ,
        s_valid: inner_tx_valid,
        s_ready: inner_tx_ready,

        m_first: m_up_tx_first,
        m_last : m_up_tx_last ,
        m_data : m_up_tx_data ,
        m_valid: m_up_tx_valid,
        m_ready: m_up_tx_ready,
    );



    // -------------------------------------
    // Functions
    // -------------------------------------


    // 同期タイマ(スレーブ)
    inst u_etherneco_synctimer_slave: etherneco_synctimer_slave #(
        TIMER_WIDTH      : TIMER_WIDTH      ,
        NUMERATOR        : NUMERATOR        ,
        DENOMINATOR      : DENOMINATOR      ,
        ADJ_COUNTER_WIDTH: ADJ_COUNTER_WIDTH,
        ADJ_CALC_WIDTH   : ADJ_CALC_WIDTH   ,
        ADJ_ERROR_WIDTH  : ADJ_ERROR_WIDTH  ,
        ADJ_ERROR_Q      : ADJ_ERROR_Q      ,
        ADJ_ADJUST_WIDTH : ADJ_ADJUST_WIDTH ,
        ADJ_ADJUST_Q     : ADJ_ADJUST_Q     ,
        ADJ_PERIOD_WIDTH : ADJ_PERIOD_WIDTH ,
        ADJ_PHASE_WIDTH  : ADJ_PHASE_WIDTH  ,
    ) (
        reset: reset,
        clk  : clk  ,

        current_time: current_time,

        node_id: outer_rx_node,

        outer_rx_start: outer_rx_start,
        outer_rx_error: outer_rx_error,
        outer_rx_end  : outer_rx_end  ,

        s_outer_rx_first: outer_rx_first,
        s_outer_rx_last : outer_rx_last ,
        s_outer_rx_data : outer_rx_data ,
        s_outer_rx_valid: outer_rx_valid,

        m_outer_tx_first: outer_tx_first,
        m_outer_tx_last : outer_tx_last ,
        m_outer_tx_data : outer_tx_data ,
        m_outer_tx_valid: outer_tx_valid,

        inner_rx_start: inner_rx_start,
        inner_rx_error: inner_rx_error,
        inner_rx_end  : inner_rx_end  ,

        s_inner_rx_first: inner_rx_first,
        s_inner_rx_last : inner_rx_last ,
        s_inner_rx_data : inner_rx_data ,
        s_inner_rx_valid: inner_rx_valid,

        m_inner_tx_first: inner_tx_first,
        m_inner_tx_last : inner_tx_last ,
        m_inner_tx_data : inner_tx_data ,
        m_inner_tx_valid: inner_tx_valid,

    );
    */


    ///

endmodule
