module jellyvl_stream_position #(
    parameter int unsigned NUMBER_WIDTH = 8     ,
    parameter int unsigned COUNT_WIDTH  = 16    ,
    parameter int unsigned OFFSET       = 0     ,
    parameter int unsigned LENGTH       = 32    ,
    parameter int unsigned STEP         = LENGTH
) (
    input logic reset,
    input logic clk  ,
    input logic cke  ,

    input logic [NUMBER_WIDTH-1:0] number,

    input logic stream_first ,
    input logic stream_enable,
    input logic stream_valid ,

    output logic                   position_first,
    output logic                   position_last ,
    output logic [COUNT_WIDTH-1:0] position_count,
    output logic                   position_valid
);

    logic offset_enable;
    if (OFFSET > 0) begin :offset
        localparam int unsigned OFFSET_WIDTH = $clog2(OFFSET + 1);
        localparam type         t_offset     = logic [OFFSET_WIDTH-1:0];

        t_offset offset_count;
        always_ff @ (posedge clk) begin
            if (reset) begin
                offset_enable <= 1'b0;
                offset_count  <= 'x;
            end else begin
                if (stream_valid) begin
                    if (stream_enable) begin
                        if (stream_first || !offset_enable) begin
                            offset_count  <= '0;
                            offset_enable <= (OFFSET == 0);
                        end else begin
                            if (!offset_enable) begin
                                offset_count  <= offset_count + t_offset'(1);
                                offset_enable <= offset_count == t_offset'((OFFSET - 1));
                            end
                        end
                    end else begin
                        offset_enable <= 1'b0;
                        offset_count  <= 'x;
                    end
                end

                if (position_valid && position_last) begin
                    offset_enable <= 1'b0;
                end
            end
        end
    end else begin :offset_bypass
        assign offset_enable = stream_enable;
    end

    localparam int unsigned LENGTH_WIDTH = $clog2(LENGTH + 1);

    /*
    var num_count:  input  logic<NUMBER_WIDTH>,
    var step_count: input  logic<NUMBER_WIDTH>,
    var size_count: input  logic<NUMBER_WIDTH>,

    always_ff (clk, reset) {
        if_reset {

        }
        else {
            if stream_valid {
                if stream_first {
                    number 
                }
                if stream_enable {
                    if 
                }

            }
            else {
                position_count = '0;
            }
        }
    }
    */

endmodule
