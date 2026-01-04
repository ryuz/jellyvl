module jellyvl_cdc_array_single #(
    parameter int signed DEST_SYNC_FF   = 4      ,
    parameter int signed SIM_ASSERT_CHK = 0      ,
    parameter bit        SRC_INPUT_REG  = 1      ,
    parameter int signed WIDTH          = 2      ,
    parameter            DEVICE         = "RTL"  ,
    parameter            SIMULATION     = "false",
    parameter            DEBUG          = "false"
) (
    input  var logic             src_clk ,
    input  var logic [WIDTH-1:0] src_in  ,
    input  var logic             dest_clk,
    output var logic [WIDTH-1:0] dest_out
);

    if ((DEVICE == "SPARTAN6" || DEVICE == "VIRTEX6" || DEVICE == "7SERIES" || DEVICE == "ULTRASCALE" || DEVICE == "ULTRASCALE_PLUS" || DEVICE == "ULTRASCALE_PLUS_ES1" || DEVICE == "ULTRASCALE_PLUS_ES2" || DEVICE == "VERSAL_AI_CORE" || DEVICE == "VERSAL_AI_CORE_ES1" || DEVICE == "VERSAL_AI_CORE_ES2" || DEVICE == "VERSAL_PRIME" || DEVICE == "VERSAL_PRIME_ES1" || DEVICE == "VERSAL_PRIME_ES2")) begin :xilinx

        xpm_cdc_array_single #(
            .DEST_SYNC_FF   (DEST_SYNC_FF  ),
            .SIM_ASSERT_CHK (SIM_ASSERT_CHK),
            .SRC_INPUT_REG  (SRC_INPUT_REG ),
            .WIDTH          (WIDTH         )
        ) u_xpm_cdc_array_single (
            .src_clk  (src_clk ),
            .src_in   (src_in  ),
            .dest_clk (dest_clk),
            .dest_out (dest_out)
        );

    end else begin :rtl
        logic [WIDTH-1:0] src_in_reg;
        always_ff @ (posedge src_clk) begin
            src_in_reg <= src_in;
        end
        (* 
        ASYNC_REG = "TRUE" *)
        logic [WIDTH-1:0] dest_out_reg [0:DEST_SYNC_FF-1];

        always_ff @ (posedge dest_clk) begin
            dest_out_reg[0] <= ((SRC_INPUT_REG) ? ( src_in_reg ) : ( src_in ));
            for (int unsigned i = 1; i < DEST_SYNC_FF; i++) begin
                dest_out_reg[i] <= dest_out_reg[i - 1];
            end
        end

        always_comb dest_out = dest_out_reg[DEST_SYNC_FF - 1];
    end
endmodule
//# sourceMappingURL=jellyvl_cdc_array_single.sv.map
