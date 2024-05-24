module jellyvl_synctimer_timer #(
    parameter int unsigned NUMERATOR   = 10,
    parameter int unsigned DENOMINATOR = 3 ,
    parameter int unsigned TIMER_WIDTH = 64
) (
    input logic rst,
    input logic clk,

    input logic [TIMER_WIDTH-1:0] set_time ,
    input logic                   set_valid,

    input  logic adjust_sign ,
    input  logic adjust_valid,
    output logic adjust_ready,

    output logic [TIMER_WIDTH-1:0] current_time
);

    localparam int unsigned COUNT_NUM     = NUMERATOR / DENOMINATOR;
    localparam int unsigned COUNT_ERR     = NUMERATOR % DENOMINATOR;
    localparam int unsigned COUNTER_WIDTH = (($clog2(COUNT_NUM + 2) > 0) ? (
        $clog2(COUNT_NUM + 2)
    ) : (
        1
    ));

    localparam type t_count = logic [COUNTER_WIDTH-1:0];
    localparam type t_time  = logic [TIMER_WIDTH-1:0];

    t_count add_value;

    if (COUNT_ERR == 0) begin :simple
        // 誤差なし
        always_ff @ (posedge clk) begin
            if (rst) begin
                add_value <= '0;
            end else begin
                add_value <= t_count'(COUNT_NUM);
                if (adjust_valid && adjust_ready) begin
                    if (adjust_sign) begin
                        add_value <= t_count'((COUNT_NUM - 1));
                    end else begin
                        add_value <= t_count'((COUNT_NUM + 1));
                    end
                end
            end
        end
        always_comb adjust_ready = 1'b1;
    end else begin :with_err
        // 分数の誤差あり
        t_count err_value;
        logic   carry    ;
        always_comb carry     = err_value >= t_count'((DENOMINATOR - COUNT_ERR));

        always_ff @ (posedge clk) begin
            if (rst) begin
                add_value <= '0;
                err_value <= '0;
            end else begin
                if (carry) begin
                    err_value <= err_value - t_count'((DENOMINATOR - COUNT_ERR));
                    if (adjust_ready) begin
                        add_value <= t_count'(COUNT_NUM);
                    end else begin
                        add_value <= t_count'((COUNT_NUM + 1));
                    end
                end else begin
                    err_value <= err_value + t_count'(COUNT_ERR);
                    if (adjust_ready) begin
                        add_value <= t_count'((COUNT_NUM + 1));
                    end else begin
                        add_value <= t_count'(COUNT_NUM);
                    end
                end
            end
        end
        always_comb adjust_ready = adjust_valid && (carry == adjust_sign);
    end

    // timer counter
    always_ff @ (posedge clk) begin
        if (rst) begin
            current_time <= '0;
        end else begin
            current_time <= current_time + t_time'(add_value);
            if (set_valid) begin
                current_time <= set_time;
            end
        end
    end
endmodule
