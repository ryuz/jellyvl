module jellyvl_cdc_pulse #(
    parameter int signed DEST_SYNC_FF   = 4      ,
    parameter int signed INIT_SYNC_FF   = 0      ,
    parameter int signed REG_OUTPUT     = 0      ,
    parameter bit        RST_USED       = 1      ,
    parameter int signed SIM_ASSERT_CHK = 0      ,
    parameter            DEVICE         = "RTL"  ,
    parameter            SIMULATION     = "false",
    parameter            DEBUG          = "false"
) (
    output var logic dest_pulse,
    input  var logic dest_clk  ,
    input  var logic dest_rst  ,
    input  var logic src_clk   ,
    input  var logic src_pulse ,
    input  var logic src_rst   
);

    if ((DEVICE == "SPARTAN6" || DEVICE == "VIRTEX6" || DEVICE == "7SERIES" || DEVICE == "ULTRASCALE" || DEVICE == "ULTRASCALE_PLUS" || DEVICE == "ULTRASCALE_PLUS_ES1" || DEVICE == "ULTRASCALE_PLUS_ES2" || DEVICE == "VERSAL_AI_CORE" || DEVICE == "VERSAL_AI_CORE_ES1" || DEVICE == "VERSAL_AI_CORE_ES2" || DEVICE == "VERSAL_PRIME" || DEVICE == "VERSAL_PRIME_ES1" || DEVICE == "VERSAL_PRIME_ES2")) begin :xilinx

        xpm_cdc_pulse #(
            .DEST_SYNC_FF   (DEST_SYNC_FF  ),
            .INIT_SYNC_FF   (INIT_SYNC_FF  ),
            .REG_OUTPUT     (REG_OUTPUT    ),
            .RST_USED       (RST_USED      ),
            .SIM_ASSERT_CHK (SIM_ASSERT_CHK)
        ) u_xpm_cdc_pulse (
            .dest_pulse (dest_pulse),
            .dest_clk   (dest_clk  ),
            .dest_rst   (dest_rst  ),
            .src_clk    (src_clk   ),
            .src_pulse  (src_pulse ),
            .src_rst    (src_rst   )
        );

    end else begin :rtl
        // source domain
        logic src_pulse_reg ;
        logic src_toggle_reg;
        always_ff @ (posedge src_clk) begin
            if (RST_USED && src_rst) begin
                src_pulse_reg  <= 1'b0;
                src_toggle_reg <= 1'b0;
            end else begin
                if (!src_pulse_reg && src_pulse) begin
                    src_toggle_reg <= ~src_toggle_reg;
                end
                src_pulse_reg <= src_pulse;
            end
        end

        logic dest_toggle;
        jellyvl_cdc_single #(
            .DEST_SYNC_FF   (DEST_SYNC_FF  ),
            .SIM_ASSERT_CHK (SIM_ASSERT_CHK),
            .SRC_INPUT_REG  (0             ),
            .DEVICE         (DEVICE        ),
            .SIMULATION     (SIMULATION    ),
            .DEBUG          (DEBUG         )
        ) u_cdc_single (
            .src_clk  (src_clk       ),
            .src_in   (src_toggle_reg),
            .dest_clk (dest_clk      ),
            .dest_out (dest_toggle   )
        );

        // destination domain
        logic dest_toggle_reg;
        always_ff @ (posedge dest_clk) begin
            if (RST_USED && dest_rst) begin
                dest_toggle_reg <= 1'b0;
            end else begin
                dest_toggle_reg <= dest_toggle;
            end
        end

        always_comb dest_pulse = (dest_toggle != dest_toggle_reg);
    end
endmodule
//# sourceMappingURL=jellyvl_cdc_pulse.sv.map
