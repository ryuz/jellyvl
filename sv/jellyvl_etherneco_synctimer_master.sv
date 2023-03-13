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

    output logic         m_last ,
    output logic [8-1:0] m_data ,
    output logic         m_valid,
    input  logic         m_ready
);

    localparam int unsigned LENGTH = 4 + 8 + 1;

    logic [LENGTH-1:0][1-1:0] last;
    logic [LENGTH-1:0][8-1:0] data;

    always_ff @ (posedge clk) begin
        if (reset) begin
            last    <= 'x;
            data    <= 'x;
            m_valid <= 1'b0;
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

                m_valid <= 1'b1;
            end else begin
                if (m_valid && m_ready) begin
                    data    <= data    >> (8);
                    last    <= last    >> (1);
                    m_valid <=   !m_last;
                end
            end
        end
    end

    assign m_data = data[0];
    assign m_last = last[0];


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

endmodule
