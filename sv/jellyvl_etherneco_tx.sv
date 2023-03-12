module jellyvl_etherneco_tx (
    input logic reset,
    input logic clk  ,

    input logic          in_start ,
    input logic [16-1:0] in_length,

    input logic in_cancel,

    input  logic         s_last ,
    input  logic [8-1:0] s_data ,
    input  logic         s_valid,
    output logic         s_ready,

    output logic         m_first,
    output logic         m_last ,
    output logic [8-1:0] m_data ,
    output logic         m_valid,
    input  logic         m_ready
);
    typedef 
    enum logic [6-1:0] {
        STATE_IDLE = 6'b000000,
        STATE_PREAMBLE = 6'b000001,
        STATE_LENGTH = 6'b000010,
        STATE_PAYLOAD = 6'b000100,
        STATE_PADDING = 6'b001000,
        STATE_FCS = 6'b010000,
        STATE_ERROR = 6'b100000
    } STATE;

    localparam type t_length = logic [16-1:0];

    logic cke;
    assign cke = !m_valid || m_ready;

    STATE            state     ;
    t_length         count     ;
    t_length         length    ;
    logic            crc_update;
    logic            tx_first  ;
    logic            tx_last   ;
    logic    [8-1:0] tx_data   ;
    logic            tx_valid  ;

    t_length count_next;
    assign count_next = count + 1'b1;

    always_ff @ (posedge clk) begin
        if (reset) begin
            state      <= STATE_IDLE;
            count      <= 'x;
            length     <= 'x;
            crc_update <= 'x;
            tx_first   <= 'x;
            tx_last    <= 'x;
            tx_data    <= 'x;
            tx_valid   <= '0;
        end else if (cke) begin
            if (tx_valid) begin
                count <= count_next;
            end

            case (state)
                STATE_IDLE: begin
                    count      <= 'x;
                    length     <= in_length;
                    crc_update <= 'x;
                    tx_first   <= 1'bx;
                    tx_last    <= 1'bx;
                    tx_data    <= 8'hxx;
                    tx_valid   <= 1'b0;
                    if (in_start) begin
                        state    <= STATE_PREAMBLE;
                        count    <= '0;
                        length   <= in_length;
                        tx_first <= 1'b1;
                        tx_last  <= 1'b0;
                        tx_data  <= 8'h55;
                        tx_valid <= 1'b1;
                    end
                end

                STATE_PREAMBLE: begin
                    crc_update <= 'x;
                    tx_first   <= 1'b0;
                    tx_last    <= 1'b0;
                    tx_data    <= 8'h55;
                    tx_valid   <= 1'b1;
                    if (count[3:0] == 3'd6) begin
                        state      <= STATE_LENGTH;
                        count      <= '0;
                        crc_update <= 1'b1;
                        tx_first   <= 1'b0;
                        tx_last    <= 1'b0;
                        tx_data    <= 8'hd5;
                        tx_valid   <= 1'b1;
                    end
                end

                STATE_LENGTH: begin
                    crc_update <= 1'b0;
                    tx_first   <= 1'b0;
                    tx_last    <= 1'b0;
                    tx_data    <= length[7:0];
                    tx_valid   <= 1'b1;
                    if (count[0] == 1'd1) begin
                        state   <= STATE_PAYLOAD;
                        count   <= '0;
                        tx_data <= length[15:8];
                    end
                end

                STATE_PAYLOAD: begin
                    tx_first <= 1'b0;
                    tx_last  <= 1'b0;
                    tx_data  <= s_data;
                    tx_valid <= 1'b1;
                    if (s_last) begin
                        state <= STATE_PADDING;
                    end
                    if (count_next == length) begin
                        state <= STATE_FCS;
                        count <= '0;
                    end
                end

                STATE_PADDING: begin
                    tx_first <= 1'b0;
                    tx_last  <= 1'b0;
                    tx_data  <= 8'h00;
                    tx_valid <= 1'b1;
                    if (count_next == length) begin
                        state <= STATE_FCS;
                        count <= '0;
                    end
                end

                STATE_FCS: begin
                    crc_update <= 1'bx;
                    tx_first   <= 1'b0;
                    tx_last    <= (count == t_length'(3));
                    tx_data    <= 'x;
                    tx_valid   <= 1'b1;
                    if (tx_last) begin
                        state    <= STATE_IDLE;
                        count    <= 'x;
                        tx_first <= 'x;
                        tx_last  <= 'x;
                        tx_data  <= 'x;
                        tx_valid <= 1'b0;
                    end
                end

                default: begin
                    state      <= STATE_IDLE;
                    count      <= 'x;
                    length     <= 'x;
                    crc_update <= 'x;
                    tx_first   <= 1'bx;
                    tx_last    <= 1'bx;
                    tx_data    <= 'x;
                    tx_valid   <= 1'b1;
                end
            endcase

            if ((tx_valid && !tx_last && in_cancel) || (state == STATE_PAYLOAD && !s_valid) || (state == STATE_PAYLOAD && count_next == length && !s_last)) begin
                state      <= STATE_ERROR;
                count      <= 'x;
                length     <= 'x;
                crc_update <= 'x;
                tx_first   <= 1'b0;
                tx_last    <= 1'b1;
                tx_data    <= 8'h00;
                tx_valid   <= 1'b1;
            end
        end
    end


    // CRC
    logic [8-1:0]  crc_data ;
    logic          crc_valid;
    logic [32-1:0] crc_value;
    assign crc_data  = tx_data;
    assign crc_valid = tx_valid && (state == STATE_LENGTH || state == STATE_PAYLOAD || state == STATE_PADDING);

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

    logic [32-1:0] out_data;
    assign m_data   = out_data[7:0];

    always_ff @ (posedge clk) begin
        if (reset) begin
            out_data <= 'x;
            m_first  <= 'x;
            m_last   <= 'x;
            m_valid  <= 1'b0;
        end else if (cke) begin
            if (state == STATE_FCS) begin
                if (count[1:0] == '0) begin
                    out_data <= crc_value;
                end else begin
                    out_data <= out_data >> 8;
                end
            end else begin
                out_data <= {24'hxxxxxx, tx_data};
            end

            m_first <= tx_first;
            m_last  <= tx_last;
            m_valid <= tx_valid;
        end
    end

endmodule
