
// リミッター
module jellyvl_synctimer_limitter #(
    parameter int unsigned TIMER_WIDTH   = 64         , // タイマのbit幅
    parameter int unsigned LIMIT_WIDTH   = TIMER_WIDTH, // 補正限界のbit幅
    parameter bit          INIT_OVERRIDE = 1          , // 初回の補正
    parameter bit          DEBUG         = 1'b0       ,
    parameter bit          SIMULATION    = 1'b0   
) (
    input logic rst,
    input logic clk,

    input logic signed [LIMIT_WIDTH-1:0] param_limit_min,
    input logic signed [LIMIT_WIDTH-1:0] param_limit_max,

    input logic [TIMER_WIDTH-1:0] current_time,

    output logic request_renew,

    input logic [TIMER_WIDTH-1:0] correct_time ,
    input logic                   correct_renew,
    input logic                   correct_valid
);

    localparam type t_diff = logic signed [TIMER_WIDTH-1:0];

    t_diff diff_time ;
    logic  diff_valid;
    always_ff @ (posedge clk) begin
        if (rst) begin
            diff_time     <= 'x;
            diff_valid    <= 1'b0;
            request_renew <= INIT_OVERRIDE;
        end else begin
            diff_time  <= t_diff'((correct_time - current_time));
            diff_valid <= correct_valid && !correct_renew;

            if (correct_valid) begin
                request_renew <= 1'b0;
            end

            if (diff_valid) begin
                if (diff_time < t_diff'(param_limit_min) || diff_time > t_diff'(param_limit_max)) begin
                    request_renew <= 1'b1;
                end
            end
        end
    end
endmodule
//# sourceMappingURL=jellyvl_synctimer_limitter.sv.map
