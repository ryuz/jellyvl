module jellyvl_etherneco_rx #() (
    input logic reset,
    input logic clk  ,

    output logic rx_start,
    output logic rx_end  ,
    output logic rx_error,

    input logic         s_first,
    input logic         s_last ,
    input logic [8-1:0] s_data ,
    input logic         s_valid,

    output logic         m_first,
    output logic         m_last ,
    output logic [8-1:0] m_data ,
    output logic         m_valid
);
    typedef 
    enum logic [5-1:0] {
        STATE_IDLE = 5'b00000,
        STATE_LENGTH = 5'b00010,
        STATE_PAYLOAD = 5'b00100,
        STATE_FCS = 5'b01000,
        STATE_ERROR = 5'b10000
    } STATE;

    localparam type t_length = logic [16-1:0];

    STATE    state     ;
    t_length count     ;
    t_length length    ;
    logic    preamble  ;
    logic    crc_update;
    logic    crc_check ;

    t_length count_next;
    assign count_next = count + 1'b1;

    always_ff @ (posedge clk) begin
        if (reset) begin
            rx_start <= 1'b0;
            rx_end   <= 1'b0;
            rx_error <= 1'b0;

            m_first <= 'x;
            m_last  <= 'x;
            m_data  <= 'x;
            m_valid <= 1'b0;

            state      <= STATE_IDLE;
            count      <= 'x;
            length     <= 'x;
            preamble   <= 1'b0;
            crc_update <= 'x;
            crc_check  <= 1'b0;
        end else begin
            rx_start  <= 1'b0;
            rx_end    <= 1'b0;
            rx_error  <= 1'b0;
            crc_check <= 1'b0;

            if (s_valid) begin
                count <= count_next;

                case (state)
                    STATE_IDLE: begin
                        if (preamble && (s_data == 8'hd5) && (count >= 6 && count <= 8)) begin
                            state      <= STATE_LENGTH;
                            count      <= 16'd1;
                            crc_update <= 1'b0;
                        end
                        m_first <= 1'bx;
                        m_last  <= 1'bx;
                    end

                    STATE_LENGTH: begin
                        if (count[0]) begin
                            length[7:0] <= s_data;
                            crc_update  <= 1'b1;
                            m_first     <= 1'bx;
                            m_last      <= 1'bx;
                        end else begin
                            state        <= STATE_PAYLOAD;
                            count        <= 16'd1;
                            length[15:8] <= s_data;
                            m_first      <= 1'b1;
                            m_last       <= ({s_data, length[7:0]} == 16'd1);
                        end
                    end

                    STATE_PAYLOAD: begin
                        m_first <= 1'b0;
                        m_last  <= (count_next == length);
                        if (m_last) begin
                            state  <= STATE_FCS;
                            count  <= 16'd1;
                            length <= 'x;
                        end
                    end

                    STATE_FCS: begin
                        if (count == 3'd5) begin
                            state     <= STATE_IDLE;
                            crc_check <= 1'b1;
                        end
                    end

                    default: begin
                        state <= STATE_IDLE;
                    end
                endcase

                if (s_data != 8'h55) begin
                    preamble <= 1'b0;
                end

                if (s_first) begin
                    count    <= 16'd1;
                    preamble <= (s_data == 8'h55);
                    rx_start <= (state == STATE_IDLE);
                end

                if ((s_first && state != STATE_IDLE && state != STATE_ERROR) || (s_last && !(state == STATE_FCS && count == 5) && state != STATE_IDLE && state != STATE_ERROR)) begin
                    state   <= STATE_ERROR;
                    m_first <= 'x;
                    m_last  <= 'x;
                    m_data  <= 'x;
                    m_valid <= 1'b0;
                end
            end

            if (state == STATE_ERROR) begin
                state   <= STATE_IDLE;
                m_first <= 'x;
                m_last  <= 'x;
                m_data  <= 'x;
                m_valid <= 1'b0;
            end

            if (crc_check) begin
                if (crc_value == 32'h2144df1c) begin
                    rx_end <= 1'b1;
                end else begin
                    rx_error <= 1'b1;
                end
            end
        end
    end

    logic [32-1:0] crc_value;

    jelly2_calc_crc #(
        .DATA_WIDTH (8           ),
        .CRC_WIDTH  (32          ),
        .POLY_REPS  (32'h04C11DB7),
        .REVERSED   (0           )
    ) u_cacl_crc (
        .reset (reset),
        .clk   (clk  ),
        .cke   (1'b1 ),
        .
        in_update (crc_update),
        .in_data   (s_data    ),
        .in_valid  (s_valid   ),
        .
        out_crc (crc_value)
    );

    // crc_value == 0x2144df1c

endmodule
