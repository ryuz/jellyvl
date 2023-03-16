module jellyvl_etherneco_packet_rx #(
    parameter bit          DOWN_STREAM   = 1'b0,
    parameter int unsigned REPLACE_DELAY = 1   ,
    parameter int unsigned BUFFERING     = 1   ,
    parameter bit          M_REGS        = 1'b1
) (
    input logic reset,
    input logic clk  ,

    input logic         s_rx_first,
    input logic         s_rx_last ,
    input logic [8-1:0] s_rx_data ,
    input logic         s_rx_valid,

    output logic         m_tx_first,
    output logic         m_tx_last ,
    output logic [8-1:0] m_tx_data ,
    output logic         m_tx_valid,

    output logic rx_start,
    output logic rx_end  ,
    output logic rx_error,

    output logic [16-1:0] rx_length,
    output logic [8-1:0]  rx_type  ,
    output logic [8-1:0]  rx_node  ,

    output logic          payload_first,
    output logic          payload_last ,
    output logic [16-1:0] payload_pos  ,
    output logic [8-1:0]  payload_data ,
    output logic          payload_valid,

    input logic [8-1:0] replace_data ,
    input logic         replace_valid
);

    localparam int unsigned BIT_PREAMBLE = 0;
    localparam int unsigned BIT_LENGTH   = 1;
    localparam int unsigned BIT_TYPE     = 2;
    localparam int unsigned BIT_NODE     = 3;
    localparam int unsigned BIT_PAYLOAD  = 4;
    localparam int unsigned BIT_FCS      = 5;
    localparam int unsigned BIT_ERROR    = 6;

    localparam type t_state_bit = logic [7-1:0];
    typedef 
    enum logic [7-1:0] {
        STATE_IDLE = 7'b0000000,
        STATE_PREAMBLE = 7'b0000001,
        STATE_LENGTH = 7'b0000010,
        STATE_TYPE = 7'b0000100,
        STATE_NODE = 7'b0001000,
        STATE_PAYLOAD = 7'b0010000,
        STATE_FCS = 7'b0100000,
        STATE_ERROR = 7'b1000000
    } STATE;

    localparam type t_count  = logic [4-1:0];
    localparam type t_length = logic [16-1:0];

    STATE       state    ;
    t_state_bit state_bit;
    assign state_bit = t_state_bit'(state);

    t_count          count      ;
    logic            preamble   ;
    logic            fcs_rx_last;
    logic            crc_update ;
    logic            crc_check  ;
    logic   [32-1:0] crc_value  ;

    logic [2-1:0] fw_count     ;
    logic         fw_crc_update;
    logic         fw_fcs       ;
    logic         fw_first     ;
    logic         fw_last      ;
    logic [8-1:0] fw_data      ;
    logic         fw_valid     ;

    t_length payload_pos_next;
    assign payload_pos_next = payload_pos + t_length'(1);

    always_ff @ (posedge clk) begin
        if (reset) begin
            state         <= STATE_IDLE;
            count         <= 'x;
            preamble      <= 1'b0;
            payload_first <= 'x;
            payload_last  <= 'x;
            payload_pos   <= 'x;
            fcs_rx_last   <= 'x;
            crc_update    <= 'x;
            crc_check     <= 1'b0;

            rx_start  <= 1'b0;
            rx_end    <= 1'b0;
            rx_error  <= 1'b0;
            rx_length <= 'x;
            rx_type   <= 'x;
            rx_node   <= 'x;

            fw_count      <= 'x;
            fw_crc_update <= 'x;
            fw_fcs        <= 'x;
            fw_first      <= 'x;
            fw_last       <= 'x;
            fw_data       <= 'x;
            fw_valid      <= 1'b0;
        end else begin
            rx_start  <= 1'b0;
            rx_end    <= 1'b0;
            rx_error  <= 1'b0;
            crc_check <= 1'b0;

            fw_count      <= 'x;
            fw_crc_update <= 'x;
            fw_fcs        <= 'x;
            fw_first      <= 1'bx;
            fw_last       <= 1'bx;
            fw_data       <= 'x;
            fw_valid      <= 1'b0;

            if (s_rx_valid) begin
                fw_count      <= count[1:0];
                fw_crc_update <= crc_update;
                fw_fcs        <= (state == STATE_FCS);
                fw_first      <= s_rx_first;
                fw_last       <= s_rx_last;
                fw_data       <= s_rx_data;
                fw_valid      <= s_rx_valid;

                if (count != '1) begin
                    count <= count + 1'b1;
                end

                payload_first <= 1'b0;
                payload_last  <= 1'b0;
                fcs_rx_last   <= 1'b0;

                case (state)
                    STATE_IDLE: begin
                        if (s_rx_first) begin
                            if (s_rx_data == 8'h55 && !s_rx_last) begin
                                state    <= STATE_PREAMBLE;
                                rx_start <= 1'b1;
                                count    <= '0;
                            end else begin
                                // 送信開始前なので何も中継せずに止める
                                state    <= STATE_ERROR;
                                rx_error <= 1'b1;
                                count    <= 'x;
                                fw_first <= 'x;
                                fw_last  <= 'x;
                                fw_data  <= 'x;
                                fw_valid <= 1'b0;
                            end
                            crc_update <= 'x;
                        end
                    end

                    STATE_PREAMBLE: begin
                        if (count == t_count'(6)) begin
                            state      <= STATE_LENGTH;
                            count      <= '0;
                            crc_update <= 1'b0;
                        end
                    end

                    STATE_LENGTH: begin
                        if (count[0:0] == 1'b1) begin
                            rx_length[15:8] <= s_rx_data;
                            crc_update      <= 1'b1;
                            state           <= STATE_TYPE;
                            count           <= 'x;
                        end else begin
                            rx_length[7:0] <= s_rx_data;
                            crc_update     <= 1'b1;
                        end
                    end

                    STATE_TYPE: begin
                        rx_type <= s_rx_data;
                        state   <= STATE_NODE;
                        count   <= 'x;
                    end

                    STATE_NODE: begin
                        rx_node       <= s_rx_data;
                        state         <= STATE_PAYLOAD;
                        payload_first <= 1'b1;
                        payload_last  <= (rx_length == '0);
                        payload_pos   <= '0;
                        if (DOWN_STREAM) begin
                            fw_data <= s_rx_data - 8'd1;
                        end else begin
                            fw_data <= s_rx_data + 8'd1;
                        end
                    end

                    STATE_PAYLOAD: begin
                        payload_first <= 1'b0;
                        payload_last  <= (payload_pos_next == rx_length);
                        payload_pos   <= payload_pos_next;
                        if (payload_last) begin
                            state       <= STATE_FCS;
                            fcs_rx_last <= 1'b0;
                            count       <= '0;
                            rx_length   <= 'x;
                        end
                    end

                    STATE_FCS: begin
                        fcs_rx_last <= (count[1:0] == 2'd2);
                        if (fcs_rx_last) begin
                            state     <= STATE_IDLE;
                            crc_check <= 1'b1;
                        end
                    end

                    default: begin
                        state <= STATE_IDLE;
                    end
                endcase

                // 不正状態検知
                if ((s_rx_first && state != STATE_IDLE && state != STATE_ERROR) || (s_rx_last && !s_rx_first && !fcs_rx_last) || (state == STATE_PREAMBLE && !((count == 4'd6 && s_rx_data == 8'hd5) || (count != 4'd6 && s_rx_data == 8'h55)))) begin
                    // パケットを打ち切る
                    state    <= STATE_ERROR;
                    rx_error <= 1'b1;
                    fw_first <= 1'b0;
                    fw_last  <= 1'b1;
                    fw_data  <= '0;
                    fw_valid <= 1'b1;
                end
            end

            // エラー処理
            if (state == STATE_ERROR) begin
                state     <= STATE_IDLE;
                rx_type   <= 'x;
                rx_node   <= 'x;
                rx_length <= 'x;
                fw_first  <= 'x;
                fw_last   <= 'x;
                fw_data   <= 'x;
                fw_valid  <= 1'b0;
            end

            // CRC チェック
            if (crc_check) begin
                if (crc_value == 32'h2144df1c) begin
                    rx_end <= 1'b1;
                end else begin
                    rx_error <= 1'b1;
                end
            end
        end
    end

    assign payload_data  = s_rx_data;
    assign payload_valid = s_rx_valid & state_bit[BIT_PAYLOAD];

    jelly2_calc_crc #(
        .DATA_WIDTH (8           ),
        .CRC_WIDTH  (32          ),
        .POLY_REPS  (32'h04C11DB7),
        .REVERSED   (0           )
    ) u_cacl_crc_rx (
        .reset (reset),
        .clk   (clk  ),
        .cke   (1'b1 ),
        .
        in_update (crc_update),
        .in_data   (s_rx_data ),
        .in_valid  (s_rx_valid),
        .
        out_crc (crc_value)
    );



    // -----------------------------
    //  Forward
    // -----------------------------

    logic fw_ready;

    logic [2-1:0] dly_count     ;
    logic         dly_crc_update;
    logic         dly_fcs       ;
    logic         dly_first     ;
    logic         dly_last      ;
    logic [8-1:0] dly_data      ;
    logic         dly_valid     ;

    localparam type t_delay = logic [2 + 4 + 8-1:0];

    jellyvl_data_delay #(
        .t_data    (t_delay      ),
        .LATENCY   (REPLACE_DELAY),
        .INIT_DATA ('x           )
    ) u_data_delay (
        .reset (reset),
        .clk   (clk  ),
        .cke   (1'b1 ),
        .
        s_data  ({fw_count, fw_crc_update, fw_fcs, fw_first, fw_last, fw_data}),
        .s_valid (fw_valid                                                ),
        .s_ready (fw_ready                                                ),
        .
        m_data  ({dly_count, dly_crc_update, dly_fcs, dly_first, dly_last, dly_data}),
        .m_valid (dly_valid                                                     ),
        .m_ready (1'b1                                                          )
    );


    // replace & CRC
    logic [8-1:0] tx_crc_data;
    assign tx_crc_data = ((replace_valid) ? (
        replace_data
    ) : (
        dly_data
    ));

    logic [4-1:0][8-1:0] tx_crc_value;
    jelly2_calc_crc #(
        .DATA_WIDTH (8           ),
        .CRC_WIDTH  (32          ),
        .POLY_REPS  (32'h04C11DB7),
        .REVERSED   (0           )
    ) u_cacl_crc_tx (
        .reset (reset),
        .clk   (clk  ),
        .cke   (1'b1 ),
        .
        in_update (dly_crc_update),
        .in_data   (dly_data      ),
        .in_valid  (dly_valid     ),
        .
        out_crc (tx_crc_value)
    );


    // output
    logic         tx_first;
    logic         tx_last ;
    logic [8-1:0] tx_data ;
    logic         tx_valid;
    logic         tx_ready;

    always_comb begin
        tx_data = dly_data;
        if (dly_fcs) begin
            tx_data = tx_crc_value[dly_count];
        end
    end

    always_ff @ (posedge clk) begin
        if (reset) begin
            tx_first <= 'x;
            tx_last  <= 'x;
            tx_valid <= 1'b0;
        end else begin
            tx_first <= dly_first;
            tx_last  <= dly_last;
            tx_valid <= dly_valid;
        end
    end



    // 1サイクル分貯める
    localparam type t_buf = logic [2 + 8-1:0];

    logic         buf_first;
    logic         buf_last ;
    logic [8-1:0] buf_data ;
    logic         buf_valid;
    logic         buf_ready;

    jellyvl_stream_ff #(
        .t_data    (t_buf         ),
        .S_REGS    (BUFFERING > 0),
        .M_REGS    (M_REGS        ),
        .INIT_DATA ('x            )
    ) u_stream_ff (
        .reset (reset),
        .clk   (clk  ),
        .cke   (1'b1 ),
        .
        s_data  ({tx_first, tx_last, tx_data}),
        .s_valid (tx_valid                  ),
        .s_ready (tx_ready                  ),
        .
        m_data  ({buf_first, buf_last, buf_data}),
        .m_valid (buf_valid                    ),
        .m_ready (buf_ready                    )
    );

    // 1サイクル溜める
    logic buf_enable;
    always_ff @ (posedge clk) begin
        if (reset) begin
            buf_enable <= 1'b0;
        end else begin
            if (buf_valid) begin
                buf_enable <= 1'b1;
            end
            if (buf_valid && buf_ready && buf_last) begin
                buf_enable <= 1'b0;
            end
        end
    end

    assign buf_ready = buf_enable;

    assign m_tx_first = buf_first;
    assign m_tx_last  = buf_last;
    assign m_tx_data  = buf_data;
    assign m_tx_valid = buf_valid & buf_enable;

endmodule
