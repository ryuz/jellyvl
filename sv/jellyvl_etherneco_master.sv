module jellyvl_etherneco_master #(
    parameter int unsigned TIMER_WIDTH = 64, // タイマのbit幅
    parameter int unsigned NUMERATOR   = 8 , // クロック周期の分子
    parameter int unsigned DENOMINATOR = 1  // クロック周期の分母
) (
    input logic reset,
    input logic clk  ,

    output logic [TIMER_WIDTH-1:0] current_time,

    output logic         m_down_tx_first,
    output logic         m_down_tx_last ,
    output logic [8-1:0] m_down_tx_data ,
    output logic         m_down_tx_valid,
    input  logic         m_down_tx_ready,
    input  logic         s_down_rx_first,
    input  logic         s_down_rx_last ,
    input  logic [8-1:0] s_down_rx_data ,
    input  logic         s_down_rx_valid,

    output logic         m_up_tx_first,
    output logic         m_up_tx_last ,
    output logic [8-1:0] m_up_tx_data ,
    output logic         m_up_tx_valid,
    input  logic         m_up_tx_ready,
    input  logic         s_up_rx_first,
    input  logic         s_up_rx_last ,
    input  logic [8-1:0] s_up_rx_data ,
    input  logic         s_up_rx_valid
);


    // -------------------------------------
    //  Ring bus
    // -------------------------------------

    // Outer ring TX (send command)
    logic         cmd_tx_payload_last ;
    logic [8-1:0] cmd_tx_payload_data ;
    logic         cmd_tx_payload_valid;
    logic         cmd_tx_payload_ready;

    jellyvl_etherneco_packet_tx u_etherneco_packet_tx_up (
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
        s_payload_last  (cmd_tx_payload_last ),
        .s_payload_data  (cmd_tx_payload_data ),
        .s_payload_valid (cmd_tx_payload_valid),
        .s_payload_ready (cmd_tx_payload_ready),
        .
        m_tx_first (m_down_tx_first),
        .m_tx_last  (m_down_tx_last ),
        .m_tx_data  (m_down_tx_data ),
        .m_tx_valid (m_down_tx_valid),
        .m_tx_ready (m_down_tx_ready)
    );


    // Outer ring RX and Inner ring TX (return)
    logic          return_rx_start ;
    logic          return_rx_end   ;
    logic          return_rx_error ;
    logic [16-1:0] return_rx_length;
    logic [8-1:0]  return_rx_type  ;
    logic [8-1:0]  return_rx_node  ;

    logic          return_payload_first;
    logic          return_payload_last ;
    logic [16-1:0] return_payload_pos  ;
    logic [8-1:0]  return_payload_data ;
    logic          return_payload_valid;
    logic [8-1:0]  return_replace_data ;
    logic          return_replace_valid;

    jellyvl_etherneco_packet_rx #(
        .DOWN_STREAM   (1'b1),
        .REPLACE_DELAY (1   )
    ) u_etherneco_packet_return (
        .reset (reset),
        .clk   (clk  ),
        .
        s_rx_first (s_up_rx_first),
        .s_rx_last  (s_up_rx_last ),
        .s_rx_data  (s_up_rx_data ),
        .s_rx_valid (s_up_rx_valid),
        .
        m_tx_first (m_up_tx_first),
        .m_tx_last  (m_up_tx_last ),
        .m_tx_data  (m_up_tx_data ),
        .m_tx_valid (m_up_tx_valid),
        .
        rx_start      (return_rx_start     ),
        .rx_end        (return_rx_end       ),
        .rx_error      (return_rx_error     ),
        .rx_length     (return_rx_length    ),
        .rx_type       (return_rx_type      ),
        .rx_node       (return_rx_node      ),
        .payload_first (return_payload_first),
        .payload_last  (return_payload_last ),
        .payload_pos   (return_payload_pos  ),
        .payload_data  (return_payload_data ),
        .payload_valid (return_payload_valid),
        .replace_data  (return_replace_data ),
        .replace_valid (return_replace_valid)
    );


    // Inner ring RX (receive response)
    logic          resp_rx_start ;
    logic          resp_rx_end   ;
    logic          resp_rx_error ;
    logic [16-1:0] resp_rx_length;
    logic [8-1:0]  resp_rx_type  ;
    logic [8-1:0]  resp_rx_node  ;

    logic         terminate_first;
    logic         terminate_last ;
    logic [8-1:0] terminate_data ;
    logic         terminate_valid;

    logic          resp_payload_first;
    logic          resp_payload_last ;
    logic [16-1:0] resp_payload_pos  ;
    logic [8-1:0]  resp_payload_data ;
    logic          resp_payload_valid;
    logic [8-1:0]  resp_replace_data ;
    logic          resp_replace_valid;

    jellyvl_etherneco_packet_rx #(
        .DOWN_STREAM   (1'b0),
        .REPLACE_DELAY (0   )
    ) u_etherneco_packet_down (
        .reset (reset),
        .clk   (clk  ),
        .
        s_rx_first (s_down_rx_first),
        .s_rx_last  (s_down_rx_last ),
        .s_rx_data  (s_down_rx_data ),
        .s_rx_valid (s_down_rx_valid),
        .
        m_tx_first (terminate_first),
        .m_tx_last  (terminate_last ),
        .m_tx_data  (terminate_data ),
        .m_tx_valid (terminate_valid),
        .
        rx_start  (resp_rx_start ),
        .rx_end    (resp_rx_end   ),
        .rx_error  (resp_rx_error ),
        .rx_length (resp_rx_length),
        .rx_type   (resp_rx_type  ),
        .rx_node   (resp_rx_node  ),
        .
        payload_first (resp_payload_first),
        .payload_last  (resp_payload_last ),
        .payload_pos   (resp_payload_pos  ),
        .payload_data  (resp_payload_data ),
        .payload_valid (resp_payload_valid),
        .replace_data  (resp_replace_data ),
        .replace_valid (resp_replace_valid)
    );

    assign resp_replace_data  = '0;
    assign resp_replace_valid = '0;




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
        m_cmd_tx_last  (cmd_tx_payload_last ),
        .m_cmd_tx_data  (cmd_tx_payload_data ),
        .m_cmd_tx_valid (cmd_tx_payload_valid),
        .m_cmd_tx_ready (cmd_tx_payload_ready),
        .
        return_rx_start      (return_rx_start     ),
        .return_rx_end        (return_rx_end       ),
        .return_rx_error      (return_rx_error     ),
        .return_rx_length     (return_rx_length    ),
        .return_rx_type       (return_rx_type      ),
        .return_rx_node       (return_rx_node      ),
        .return_payload_first (return_payload_first),
        .return_payload_last  (return_payload_last ),
        .return_payload_pos   (return_payload_pos  ),
        .return_payload_data  (return_payload_data ),
        .return_payload_valid (return_payload_valid),
        .return_replace_data  (return_replace_data ),
        .return_replace_valid (return_replace_valid),
        .
        resp_rx_start      (resp_rx_start     ),
        .resp_rx_end        (resp_rx_end       ),
        .resp_rx_error      (resp_rx_error     ),
        .resp_rx_length     (resp_rx_length    ),
        .resp_rx_type       (resp_rx_type      ),
        .resp_rx_node       (resp_rx_node      ),
        .resp_payload_first (resp_payload_first),
        .resp_payload_last  (resp_payload_last ),
        .resp_payload_pos   (resp_payload_pos  ),
        .resp_payload_data  (resp_payload_data ),
        .resp_payload_valid (resp_payload_valid)
    );

endmodule
