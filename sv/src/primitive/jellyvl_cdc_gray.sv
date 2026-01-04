module jellyvl_cdc_gray #(
    parameter int signed DEST_SYNC_FF          = 4      ,
    parameter int signed SIM_ASSERT_CHK        = 0      ,
    parameter int signed SIM_LOSSLESS_GRAY_CHK = 0      ,
    parameter int signed WIDTH                 = 2      ,
    parameter            DEVICE                = "RTL"  ,
    parameter            SIMULATION            = "false",
    parameter            DEBUG                 = "false"
) (
    input  var logic             src_clk     ,
    input  var logic [WIDTH-1:0] src_in_bin  ,
    input  var logic             dest_clk    ,
    output var logic [WIDTH-1:0] dest_out_bin
);

    function automatic logic [WIDTH-1:0] binary_to_graycode(
        input var logic [WIDTH-1:0] binary
    ) ;
        logic [WIDTH-1:0] graycode                          ;
        graycode[($size(graycode, 1) - 1)] = binary[($size(binary, 1) - 1)];
        for (int signed i = (WIDTH - 1) - 1; i >= 0; i--) begin
            if (i != signed'(int'((WIDTH - 1)))) begin
                graycode[unsigned'(int'(i))] = binary[unsigned'(int'((i + 1)))] ^ binary[unsigned'(int'(i))];
            end
        end
        return graycode;
    endfunction

    function automatic logic [WIDTH-1:0] graycode_to_binary(
        input var logic [WIDTH-1:0] graycode
    ) ;
        logic [WIDTH-1:0] binary                        ;
        binary[($size(binary, 1) - 1)] = graycode[($size(graycode, 1) - 1)];
        for (int signed i = (WIDTH - 1) - 1; i >= 0; i--) begin
            if (i != signed'(int'((WIDTH - 1)))) begin
                binary[unsigned'(int'(i))] = binary[unsigned'(int'((i + 1)))] ^ graycode[unsigned'(int'(i))];
            end
        end
        return binary;
    endfunction

    if ((DEVICE == "SPARTAN6" || DEVICE == "VIRTEX6" || DEVICE == "7SERIES" || DEVICE == "ULTRASCALE" || DEVICE == "ULTRASCALE_PLUS" || DEVICE == "ULTRASCALE_PLUS_ES1" || DEVICE == "ULTRASCALE_PLUS_ES2" || DEVICE == "VERSAL_AI_CORE" || DEVICE == "VERSAL_AI_CORE_ES1" || DEVICE == "VERSAL_AI_CORE_ES2" || DEVICE == "VERSAL_PRIME" || DEVICE == "VERSAL_PRIME_ES1" || DEVICE == "VERSAL_PRIME_ES2")) begin :xilinx

        xpm_cdc_gray #(
            .DEST_SYNC_FF          (DEST_SYNC_FF         ),
            .SIM_ASSERT_CHK        (SIM_ASSERT_CHK       ),
            .SIM_LOSSLESS_GRAY_CHK (SIM_LOSSLESS_GRAY_CHK),
            .WIDTH                 (WIDTH                )
        ) u_xpm_cdc_gray (
            .src_clk      (src_clk     ),
            .src_in_bin   (src_in_bin  ),
            .dest_clk     (dest_clk    ),
            .dest_out_bin (dest_out_bin)
        );

    end else begin :rtl
        logic [WIDTH-1:0] src_graycode ;
        logic [WIDTH-1:0] dest_graycode;

        always_comb src_graycode = binary_to_graycode(src_in_bin);

        jellyvl_cdc_array_single #(
            .DEST_SYNC_FF   (DEST_SYNC_FF  ),
            .SIM_ASSERT_CHK (SIM_ASSERT_CHK),
            .SRC_INPUT_REG  (1             ),
            .WIDTH          (WIDTH         ),
            .DEVICE         (DEVICE        ),
            .SIMULATION     (SIMULATION    ),
            .DEBUG          (DEBUG         )
        ) u_cdc_array_single (
            .src_clk  (src_clk      ),
            .src_in   (src_graycode ),
            .dest_clk (dest_clk     ),
            .dest_out (dest_graycode)
        );

        always_comb dest_out_bin = graycode_to_binary(dest_graycode);
    end
endmodule
//# sourceMappingURL=jellyvl_cdc_gray.sv.map
