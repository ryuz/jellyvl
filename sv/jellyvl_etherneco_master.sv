module jellyvl_etherneco_master #(
    parameter int unsigned TIMER_WIDTH = 64, // タイマのbit幅
    parameter int unsigned NUMERATOR   = 8 , // クロック周期の分子
    parameter int unsigned DENOMINATOR = 1  // クロック周期の分母
) (
    input logic reset,
    input logic clk  ,

    output logic [TIMER_WIDTH-1:0] current_time,

    input  logic         s_down_rx_first,
    input  logic         s_down_rx_last ,
    input  logic [8-1:0] s_down_rx_data ,
    input  logic         s_down_rx_valid,
    output logic         m_down_tx_first,
    output logic         m_down_tx_last ,
    output logic [8-1:0] m_down_tx_data ,
    output logic         m_down_tx_valid,
    input  logic         m_down_tx_ready,

    input  logic         s_up_rx_first,
    input  logic         s_up_rx_last ,
    input  logic [8-1:0] s_up_rx_data ,
    input  logic         s_up_rx_valid,
    output logic         m_up_tx_first,
    output logic         m_up_tx_last ,
    output logic [8-1:0] m_up_tx_data ,
    output logic         m_up_tx_valid,
    input  logic         m_up_tx_ready
);

    // -------------------------------------
    //  Control
    // -------------------------------------

    localparam int unsigned PERIOD_WIDTH = 32;

    logic          timsync_trigger ;
    logic          timsync_override;
    logic [8-1:0]  request_type    ;
    logic [8-1:0]  request_node    ;
    logic [16-1:0] request_length  ;

    // とりあえず時間合わせパケットに固定
    assign request_type   = 8'h10;
    assign request_node   = 8'h00;
    assign request_length = 16'd13 - 16'd1;


    // 通信タイミング生成
    jellyvl_periodic_trigger #(
        .TIMER_WIDTH  (TIMER_WIDTH ),
        .PERIOD_WIDTH (PERIOD_WIDTH)
    ) u_periodic_trigger (
        .reset (reset),
        .clk   (clk  ),
        .
        enable (1'b1     ),
        .phase  ('0       ),
        .period (32'd20000),
        .
        current_time (current_time),
        .
        trigger (timsync_trigger)
    );

    always_ff @ (posedge clk) begin
        if (reset) begin
            timsync_override <= 1'b1;
        end else begin
            if (timsync_trigger) begin
                timsync_override <= 1'b0;
            end
        end
    end


    // -------------------------------------
    //  Outer loop (request)
    // -------------------------------------

    logic         outer_tx_last ;
    logic [8-1:0] outer_tx_data ;
    logic         outer_tx_valid;
    logic         outer_tx_ready;

    // タイマ合わせマスター
    jellyvl_etherneco_synctimer_master #(
        .TIMER_WIDTH (TIMER_WIDTH),
        .NUMERATOR   (NUMERATOR  ),
        .DENOMINATOR (DENOMINATOR)
    ) u_etherneco_synctimer_master (
        .reset (reset),
        .clk   (clk  ),
        .
        current_time (current_time),
        .
        sync_start    (timsync_trigger ),
        .sync_override (timsync_override),
        .
        m_last  (outer_tx_last ),
        .m_data  (outer_tx_data ),
        .m_valid (outer_tx_valid),
        .m_ready (outer_tx_ready)
    );

    jellyvl_etherneco_packet_tx u_etherneco_packet_tx_outer (
        .reset (reset),
        .clk   (clk  ),
        .
        tx_start  (timsync_trigger),
        .tx_length (request_length ),
        .tx_type   (request_type   ),
        .tx_node   (request_node   ),
        .
        tx_cancel (1'b0),
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

    /*
    var outer_rx_last : logic   ;
    var outer_rx_data : logic<8>;
    var outer_rx_valid: logic   ;
    var outer_rx_ready: logic   ;
    */

endmodule
