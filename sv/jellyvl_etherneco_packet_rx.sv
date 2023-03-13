module jellyvl_etherneco_packet_rx #() (
    input logic reset,
    input logic clk  ,

    output logic          rx_start ,
    output logic          rx_end   ,
    output logic          rx_error ,
    output logic [16-1:0] rx_length,
    output logic [8-1:0]  rx_type  ,
    output logic [8-1:0]  rx_node  ,

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
    enum logic [7-1:0] {
        STATE_IDLE = 7'b0000000,
        STATE_LENGTH = 7'b0000010,
        STATE_TYPE = 7'b0000100,
        STATE_NODE = 7'b0001000,
        STATE_PAYLOAD = 7'b0010000,
        STATE_FCS = 7'b0100000,
        STATE_ERROR = 7'b1000000
    } STATE;

    localparam type t_count  = logic [4-1:0];
    localparam type t_length = logic [16-1:0];

    STATE             state        ;
    t_count           count        ;
    t_length          length       ;
    logic             preamble     ;
    logic             payload_first;
    logic             payload_last ;
    logic             fcs_last     ;
    logic             crc_update   ;
    logic             crc_check    ;
    logic    [32-1:0] crc_value    ;

    t_length length_next;
    assign length_next = length - 1'b1;

    always_ff @ (posedge clk) begin
        if (reset) begin
            rx_start  <= 1'b0;
            rx_end    <= 1'b0;
            rx_error  <= 1'b0;
            rx_length <= 'x;
            rx_type   <= 'x;
            rx_node   <= 'x;

            m_first <= 'x;
            m_last  <= 'x;
            m_data  <= 'x;
            m_valid <= 1'b0;

            state         <= STATE_IDLE;
            count         <= 'x;
            length        <= 'x;
            preamble      <= 1'b0;
            payload_first <= 1'bx;
            payload_last  <= 1'bx;
            fcs_last      <= 'x;
            crc_update    <= 'x;
            crc_check     <= 1'b0;
        end else begin
            rx_start  <= 1'b0;
            rx_end    <= 1'b0;
            rx_error  <= 1'b0;
            crc_check <= 1'b0;
            m_first   <= 1'bx;
            m_last    <= 1'bx;
            m_data    <= s_data;
            m_valid   <= 1'b0;

            if (s_valid) begin
                if (count != '1) begin
                    count <= count + 1'b1;
                end

                payload_first <= 1'bx;
                payload_last  <= 1'bx;
                fcs_last      <= 1'bx;

                case (state)
                    STATE_IDLE: begin
                        if (preamble && (s_data == 8'hd5) && (count >= 5 && count <= 7)) begin
                            state      <= STATE_LENGTH;
                            count      <= '0;
                            crc_update <= 1'b0;
                        end
                    end

                    STATE_LENGTH: begin
                        if (~count[0]) begin
                            length[7:0] <= s_data;
                            crc_update  <= 1'b1;
                            m_first     <= 1'bx;
                            m_last      <= 1'bx;
                        end else begin
                            length[15:8] <= s_data;
                            rx_length    <= {s_data, length[7:0]};
                            state        <= STATE_TYPE;

                            /*
                            state         = STATE::PAYLOAD;
                            count         = '0;
                            length[15:8]  = s_data;
                            payload_first = 1'b1;
                            payload_last  = ({s_data, length[7:0]} == 16'd0);
                            rx_length     = {s_data, length[7:0]};
                            */

                        end
                    end

                    STATE_TYPE: begin
                        rx_type <= s_data;
                        state   <= STATE_NODE;
                    end

                    STATE_NODE: begin
                        rx_node       <= s_data;
                        state         <= STATE_PAYLOAD;
                        payload_first <= 1'b1;
                        payload_last  <= (length == 16'd0);
                    end

                    STATE_PAYLOAD: begin
                        length        <= length_next;
                        payload_first <= 1'b0;
                        payload_last  <= (length_next == '0);
                        m_first       <= payload_first;
                        m_last        <= payload_last;
                        m_valid       <= 1'b1;
                        if (payload_last) begin
                            state    <= STATE_FCS;
                            fcs_last <= 1'b0;
                            count    <= '0;
                            length   <= 'x;
                        end
                    end

                    STATE_FCS: begin
                        fcs_last <= (count[1:0] == 2'd2);
                        if (fcs_last) begin
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
                    count    <= '0;
                    preamble <= (s_data == 8'h55);
                    rx_start <= (state == STATE_IDLE);
                end

                if ((s_first && state != STATE_IDLE && state != STATE_ERROR) || (s_last && !(state == STATE_FCS && fcs_last) && state != STATE_IDLE && state != STATE_ERROR)) begin
                    state    <= STATE_ERROR;
                    rx_error <= 1'b1;
                    m_first  <= 'x;
                    m_last   <= 'x;
                    m_data   <= 'x;
                    m_valid  <= 1'b0;
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

endmodule
