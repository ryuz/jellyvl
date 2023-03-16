module jellyvl_etherneco_synctimer_master #(
    parameter int unsigned TIMER_WIDTH = 64, // タイマのbit幅
    parameter int unsigned NUMERATOR   = 10, // クロック周期の分子
    parameter int unsigned DENOMINATOR = 3  // クロック周期の分母

) (
    input logic reset,
    input logic clk  ,

    output logic [TIMER_WIDTH-1:0] current_time,

    input logic sync_start   ,
    input logic sync_override,

    output logic         m_cmd_tx_last ,
    output logic [8-1:0] m_cmd_tx_data ,
    output logic         m_cmd_tx_valid,
    input  logic         m_cmd_tx_ready,

    input  logic          ret_rx_start     ,
    input  logic          ret_rx_end       ,
    input  logic          ret_rx_error     ,
    input  logic [16-1:0] ret_rx_length    ,
    input  logic [8-1:0]  ret_rx_type      ,
    input  logic [8-1:0]  ret_rx_node      ,
    input  logic          ret_payload_first,
    input  logic          ret_payload_last ,
    input  logic [16-1:0] ret_payload_pos  ,
    input  logic [8-1:0]  ret_payload_data ,
    input  logic          ret_payload_valid,
    output logic [8-1:0]  ret_replace_data ,
    output logic          ret_replace_valid,

    input logic          res_rx_start     ,
    input logic          res_rx_end       ,
    input logic          res_rx_error     ,
    input logic [16-1:0] res_rx_length    ,
    input logic [8-1:0]  res_rx_type      ,
    input logic [8-1:0]  res_rx_node      ,
    input logic          res_payload_first,
    input logic          res_payload_last ,
    input logic [16-1:0] res_payload_pos  ,
    input logic [8-1:0]  res_payload_data ,
    input logic          res_payload_valid
);


    // タイマ
    logic adjust_ready;
    jellyvl_synctimer_timer #(
        .NUMERATOR   (NUMERATOR  ),
        .DENOMINATOR (DENOMINATOR),
        .TIMER_WIDTH (TIMER_WIDTH)
    ) u_synctimer_timer (
        .reset (reset),
        .clk   (clk  ),
        .
        set_time  ('0  ),
        .set_valid (1'b0),
        .
        adjust_sign  (1'b0        ),
        .adjust_valid (1'b0        ),
        .adjust_ready (adjust_ready),
        .
        current_time (current_time)
    );

    localparam int unsigned LENGTH = 4 + 8 + 1;

    logic [LENGTH-1:0][1-1:0] last;
    logic [LENGTH-1:0][8-1:0] data;

    always_ff @ (posedge clk) begin
        if (reset) begin
            last           <= 'x;
            data           <= 'x;
            m_cmd_tx_valid <= 1'b0;
        end else begin
            if (sync_start) begin
                // command_id
                data[0] <= ((sync_override) ? (
                    8'h01
                ) : (
                    8'h00
                ));
                last[0] <= 1'b0;

                // time
                data[8:1] <= current_time;
                last[8:1] <= 8'h00;

                // offset
                data[12:9] <= 32'd1000;
                last[12:9] <= 4'b1000;

                m_cmd_tx_valid <= 1'b1;
            end else begin
                if (m_cmd_tx_valid && m_cmd_tx_ready) begin
                    data           <= data           >> (8);
                    last           <= last           >> (1);
                    m_cmd_tx_valid <=   !m_cmd_tx_last;
                end
            end
        end
    end

    assign m_cmd_tx_data = data[0];
    assign m_cmd_tx_last = last[0];

endmodule
