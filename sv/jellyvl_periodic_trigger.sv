module jellyvl_periodic_trigger #(
    parameter int unsigned TIMER_WIDTH    = 64  ,
    parameter int unsigned PERIOD_WIDTH   = 32  ,
    parameter bit          THRASHING_MASK = 1'b1
) (
    input var logic rst,
    input var logic clk,

    input var logic                    enable,
    input var logic [PERIOD_WIDTH-1:0] phase ,
    input var logic [PERIOD_WIDTH-1:0] period,

    input var logic [TIMER_WIDTH-1:0] current_time,

    output var logic trigger
);

    localparam type t_period = logic [PERIOD_WIDTH-1:0];

    logic    trigger_valid;
    t_period base_time    ;

    t_period elapsed_time;
    always_comb elapsed_time = current_time[PERIOD_WIDTH - 1:0] - base_time;

    always_ff @ (posedge clk) begin
        if (rst) begin
            base_time     <= '0;
            trigger       <= 1'b0;
            trigger_valid <= 1'b0;
        end else begin
            if (enable) begin
                trigger       <= 1'b0;
                trigger_valid <= 1'b0;
                if (elapsed_time >= period) begin
                    base_time <= base_time + period;

                    trigger_valid <= 1'b1;
                    trigger       <= !THRASHING_MASK || !trigger_valid; // 連続していなければ発行
                end
            end else begin
                base_time     <= phase;
                trigger_valid <= 1'b0;
                trigger       <= 1'b0;
            end
        end
    end
endmodule
//# sourceMappingURL=jellyvl_periodic_trigger.sv.map
