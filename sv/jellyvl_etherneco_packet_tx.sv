module jellyvl_etherneco_packet_tx #(
    parameter int unsigned FIFO_PTR_WIDTH = 0
) (
    input logic reset,
    input logic clk  ,

    input logic start ,
    input logic cancel,

    input logic [16-1:0] param_length, // 転送サイズより1小さい値を指定(AXI方式)
    input logic [8-1:0]  param_type  ,
    input logic [8-1:0]  param_node  ,

    output logic tx_start,

    input  logic         s_payload_last ,
    input  logic [8-1:0] s_payload_data ,
    input  logic         s_payload_valid,
    output logic         s_payload_ready,

    output logic         m_tx_first,
    output logic         m_tx_last ,
    output logic [8-1:0] m_tx_data ,
    output logic         m_tx_valid,
    input  logic         m_tx_ready
);


    // -------------------------
    //  FIFO
    // -------------------------

    logic [FIFO_PTR_WIDTH + 1-1:0] fifo_free_count;
    logic [FIFO_PTR_WIDTH + 1-1:0] fifo_data_count;
    logic                          fifo_last      ;
    logic [8-1:0]                  fifo_data      ;
    logic                          fifo_valid     ;
    logic                          fifo_ready     ;

    jelly2_fifo_fwtf #(
        .DATA_WIDTH (1 + 8         ),
        .PTR_WIDTH  (FIFO_PTR_WIDTH),
        .DOUT_REGS  (0             ),
        .RAM_TYPE   ("distributed" ),
        .LOW_DEALY  (1             ),
        .S_REGS     (0             ),
        .M_REGS     (0             )
    ) u_fifo_fwtf (
        .reset        (reset                          ),
        .clk          (clk                            ),
        .cke          (1'b1                           ),
        .s_data       ({s_payload_last, s_payload_data}),
        .s_valid      (s_payload_valid                ),
        .s_ready      (s_payload_ready                ),
        .s_free_count (fifo_free_count                ),
        .m_data       ({fifo_last, fifo_data}          ),
        .m_valid      (fifo_valid                     ),
        .m_ready      (fifo_ready                     ),
        .m_data_count (fifo_data_count                )
    );


    // -------------------------
    //  core
    // -------------------------
    typedef 
    enum logic [8-1:0] {
        STATE_IDLE = 8'b00000000,
        STATE_PREAMBLE = 8'b00000001,
        STATE_LENGTH = 8'b00000010,
        STATE_TYPE = 8'b00000100,
        STATE_NODE = 8'b00001000,
        STATE_PAYLOAD = 8'b00010000,
        STATE_PADDING = 8'b00100000,
        STATE_FCS = 8'b01000000,
        STATE_ERROR = 8'b10000000
    } STATE;

    localparam type t_length = logic [16-1:0];
    localparam type t_count  = logic [3-1:0];

    logic cke;
    assign cke = !m_tx_valid || m_tx_ready;


    // ----------------------------
    //  stage 0
    // ----------------------------

    STATE    st0_state ;
    t_count  st0_count ;
    t_length st0_length;
    logic    st0_first ;
    logic    st0_last  ;

    t_count st0_count_next;
    assign st0_count_next = st0_count + 1'b1;

    t_length st0_length_next;
    assign st0_length_next = st0_length - 1'b1;

    always_ff @ (posedge clk) begin
        if (reset) begin
            st0_state  <= STATE_IDLE;
            st0_count  <= 'x;
            st0_length <= 'x;
            st0_first  <= 1'bx;
            st0_last   <= 1'bx;

        end else if (cke) begin

            st0_count <= st0_count_next;
            case (st0_state)
                STATE_IDLE: begin
                    st0_count  <= 'x;
                    st0_length <= 'x;
                    st0_first  <= 1'bx;
                    st0_last   <= 1'bx;
                    if (tx_start) begin
                        st0_state  <= STATE_PREAMBLE;
                        st0_count  <= '0;
                        st0_length <= param_length;
                        st0_first  <= 1'b0;
                        st0_last   <= 1'b0;
                    end
                end

                STATE_PREAMBLE: begin
                    st0_first <= 1'b0;
                    st0_last  <= (st0_count == 3'd5);
                    if (st0_last) begin
                        st0_state <= STATE_LENGTH;
                        st0_count <= '0;
                        st0_first <= 1'b1;
                        st0_last  <= 1'b0;
                    end
                end

                STATE_LENGTH: begin
                    st0_first <= 1'b0;
                    st0_last  <= (st0_count[0] == 1'd0);
                    if (st0_last) begin
                        st0_state <= STATE_TYPE;
                        st0_count <= '0;
                        st0_first <= 1'b1;
                        st0_last  <= 1'b1;
                    end
                end

                STATE_TYPE: begin
                    st0_first <= 1'b1;
                    st0_last  <= 1'b1;
                    st0_state <= STATE_NODE;
                    st0_count <= '0;
                end

                STATE_NODE: begin
                    st0_state <= STATE_PAYLOAD;
                    st0_count <= '0;
                    st0_first <= 1'b1;
                    st0_last  <= st0_length == 16'd0;
                end

                STATE_PAYLOAD: begin
                    st0_length <= st0_length_next;
                    st0_first  <= 1'b0;
                    st0_last   <= (st0_length_next == 0);
                    if (fifo_last) begin
                        st0_state <= STATE_PADDING;
                    end
                    if (st0_last) begin
                        st0_state  <= STATE_FCS;
                        st0_count  <= '0;
                        st0_length <= 'x;
                        st0_first  <= 1'b1;
                        st0_last   <= 1'b0;
                    end
                end

                STATE_PADDING: begin
                    st0_length <= st0_length_next;
                    st0_first  <= 1'b0;
                    st0_last   <= (st0_length_next == 0);
                    if (st0_last) begin
                        st0_state  <= STATE_FCS;
                        st0_count  <= '0;
                        st0_length <= 'x;
                        st0_first  <= 1'b1;
                        st0_last   <= 1'b0;
                    end
                end

                STATE_FCS: begin
                    st0_length <= 'x;
                    st0_first  <= 1'b0;
                    st0_last   <= st0_count == 3'd2;
                    if (st0_last) begin
                        st0_state <= STATE_IDLE;
                        st0_count <= 'x;
                    end
                end

                default: begin
                    st0_state  <= STATE_IDLE;
                    st0_count  <= 'x;
                    st0_length <= 'x;
                    st0_first  <= 1'bx;
                    st0_last   <= 1'bx;
                end
            endcase

            // エラーチェック
            if ((st0_state == STATE_PAYLOAD && !fifo_valid) // 転送中アンダーフロー
             || (st0_state == STATE_PAYLOAD && st0_last && !fifo_last)) begin // オーバーフロー
                st0_state  <= STATE_ERROR;
                st0_count  <= 'x;
                st0_length <= 'x;
                st0_first  <= 1'bx;
                st0_last   <= 1'bx;
            end

            if (cancel) begin
                st0_state  <= STATE_IDLE;
                st0_count  <= 'x;
                st0_length <= 'x;
                st0_first  <= 1'bx;
                st0_last   <= 1'bx;
            end
        end
    end

    assign fifo_ready = cke && (st0_state == STATE_PAYLOAD);

    assign tx_start = start && (st0_state == STATE_IDLE);


    // ----------------------------
    //  stage 1
    // ----------------------------

    STATE         st1_state;
    logic         st1_first;
    logic         st1_last ;
    logic [8-1:0] st1_data ;

    always_ff @ (posedge clk) begin
        if (reset) begin
            st1_state <= STATE_IDLE;
            st1_first <= 'x;
            st1_last  <= 'x;
            st1_data  <= 'x;
        end else if (cke) begin

            // stage1
            st1_state <= st0_state;
            st1_first <= st0_first;
            st1_last  <= st0_last;
            st1_data  <= 'x;

            case (st0_state)
                STATE_IDLE: begin
                    // ここだけ追い越しして1cycle稼ぐ
                    if (tx_start) begin
                        st1_state <= STATE_PREAMBLE;
                        st1_first <= 1'b1;
                        st1_last  <= 1'b0;
                        st1_data  <= 8'h55;
                    end
                end

                STATE_PREAMBLE: begin
                    st1_data <= ((st0_last) ? (
                        8'hd5
                    ) : (
                        8'h55
                    ));
                end

                STATE_LENGTH: begin
                    st1_data <= ((st0_count[0]) ? (
                        st0_length[15:8]
                    ) : (
                        st0_length[7:0]
                    ));
                end

                STATE_TYPE: begin
                    st1_data <= param_type;
                end

                STATE_NODE: begin
                    st1_data <= param_node;
                end

                STATE_PAYLOAD: begin
                    st1_data <= fifo_data;
                end

                STATE_PADDING: begin
                    st1_data <= 8'h00;
                end

                STATE_FCS: begin
                    st1_data <= 'x;
                end

                default: begin
                end
            endcase

            // キャンセル
            if (cancel) begin
                st1_state <= STATE_IDLE;
                st1_first <= 1'bx;
                st1_last  <= 1'bx;
                st1_data  <= 'x;
            end
        end
    end


    // ----------------------------
    //  stage 2
    // ----------------------------

    STATE          st2_state;
    logic          st2_first;
    logic          st2_last ;
    logic [32-1:0] st2_crc  ;
    logic [8-1:0]  st2_data ;

    always_ff @ (posedge clk) begin
        if (reset) begin
            st2_state <= STATE_IDLE;
            st2_first <= 1'bx;
            st2_last  <= 1'bx;
            st2_data  <= 'x;
        end else if (cke) begin
            st2_state <= st1_state;
            st2_first <= st1_first;
            st2_last  <= st1_last;
            st2_data  <= st1_data;

            if (cancel) begin
                st2_state <= STATE_IDLE;
                st2_first <= 1'bx;
                st2_last  <= 1'bx;
                st2_data  <= 'x;
            end
        end
    end

    // CRC
    logic          crc_update;
    logic [8-1:0]  crc_data  ;
    logic          crc_valid ;
    logic [32-1:0] crc_value ;

    jelly2_calc_crc #(
        .DATA_WIDTH (8           ),
        .CRC_WIDTH  (32          ),
        .POLY_REPS  (32'h04C11DB7),
        .REVERSED   (0           )
    ) u_cacl_crc (
        .reset (reset),
        .clk   (clk  ),
        .cke   (cke  ),
        .
        in_update (crc_update),
        .in_data   (crc_data  ),
        .in_valid  (crc_valid ),
        .
        out_crc (crc_value)
    );

    assign crc_update = !(st1_state == STATE_LENGTH && st1_first);
    assign crc_data   = st1_data;
    assign crc_valid  = (st1_state == STATE_LENGTH || st1_state == STATE_TYPE || st1_state == STATE_NODE || st1_state == STATE_PAYLOAD || st1_state == STATE_PADDING);
    assign st2_crc    = crc_value;



    // ----------------------------
    //  stage 3
    // ----------------------------

    STATE          st3_state;
    logic          st3_first;
    logic          st3_last ;
    logic [32-1:0] st3_data ;
    logic          st3_valid;

    always_ff @ (posedge clk) begin
        if (reset) begin
            st3_state <= STATE_IDLE;
            st3_first <= 1'bx;
            st3_last  <= 1'bx;
            st3_data  <= 'x;
            st3_valid <= 1'b0;

        end else if (cke) begin
            st3_state <= st2_state;
            st3_first <= st2_first && st2_state == STATE_PREAMBLE;
            st3_last  <= st2_last && st2_state == STATE_FCS;
            if (st2_state == STATE_FCS) begin
                if (st2_first) begin
                    st3_data <= st2_crc;
                end else begin
                    st3_data <= st3_data >> (8);
                end
            end else begin
                st3_data[7:0] <= st2_data;
            end
            st3_valid <= (st2_state != STATE_IDLE);

            if ((cancel && st3_valid && !st3_last) || st2_state == STATE_ERROR) begin
                st3_state     <= STATE_ERROR;
                st3_first     <= 1'b0;
                st3_last      <= 1'b1;
                st3_data[7:0] <= 8'h00;
                st3_valid     <= 1'b1;
            end
        end
    end

    assign m_tx_first = st3_first;
    assign m_tx_last  = st3_last;
    assign m_tx_data  = st3_data[7:0];
    assign m_tx_valid = st3_valid;

endmodule
