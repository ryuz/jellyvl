module jellyvl_periodic_trigger #(
    parameter int unsigned TIMER_WIDTH  = 64,
    parameter int unsigned PERIOD_WIDTH = 32
) (
    input logic reset,
    input logic clk  ,

    input logic                    enable,
    input logic [PERIOD_WIDTH-1:0] phase ,
    input logic [PERIOD_WIDTH-1:0] period,

    input logic [TIMER_WIDTH-1:0] current_time,

    output logic trigger
);

    localparam type t_period = logic [PERIOD_WIDTH-1:0];
    localparam type t_count  = logic signed [PERIOD_WIDTH + 1-1:0];

    t_period next_time;

    t_count remaining_time;
    assign remaining_time = t_count'(next_time) - t_count'(current_time[PERIOD_WIDTH - 1:0]);

    always_ff @ (posedge clk) begin
        if (reset) begin
            next_time <= '0;
            trigger   <= 1'b0;
        end else begin
            if (enable) begin
                trigger <= 1'b0;
                if (remaining_time < 0) begin
                    next_time <= next_time + period;
                    trigger   <= 1'b1;
                end
            end else begin
                next_time <= phase + period;
                trigger   <= 1'b0;
            end
        end
    end
endmodule
