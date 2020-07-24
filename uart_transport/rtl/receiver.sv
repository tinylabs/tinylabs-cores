module receiver #(
                  parameter OVERSAMPLE = 16
                  )
   (
    input wire       rx,
	output reg       rdy,
	input wire       rdy_clr,
	input wire       clk,
	input wire       clken,
	output reg [7:0] data
    );

initial begin
	rdy = 0;
	data = 0;
end

   localparam RX_STATE_START	= 2'b00;
   localparam RX_STATE_DATA		= 2'b01;
   localparam RX_STATE_STOP		= 2'b10;
   
   reg [1:0]                    state = RX_STATE_START;
   reg [$clog2(OVERSAMPLE)-1:0] sample = 0;
   reg [3:0]                    bitpos = 0;
   reg [7:0]                    scratch = 0;

always @(posedge clk) begin
	if (rdy_clr)
		rdy <= 0;

	if (clken) begin
		case (state)
		RX_STATE_START: begin
			/*
			* Start counting from the first low sample, once we've
			* sampled a full bit, start collecting data bits.
			*/
			if (!rx || sample != 0)
				sample <= sample + 1;

			if (32'(sample) == (OVERSAMPLE-1)) begin
				state <= RX_STATE_DATA;
				bitpos <= 0;
				sample <= 0;
				scratch <= 0;
			end
		end
		RX_STATE_DATA: begin
			sample <= sample + 1;
			if (32'(sample) == (OVERSAMPLE/2)) begin
				scratch[bitpos[2:0]] <= rx;
				bitpos <= bitpos + 1;
			end
			if (bitpos == 8 && 32'(sample) == (OVERSAMPLE-1))
				state <= RX_STATE_STOP;
		end
		RX_STATE_STOP: begin
			/*
			 * Our baud clock may not be running at exactly the
			 * same rate as the transmitter.  If we thing that
			 * we're at least half way into the stop bit, allow
			 * transition into handling the next start bit.
			 */
			if (32'(sample) == (OVERSAMPLE-1) || (32'(sample) >= (OVERSAMPLE/2) && !rx)) begin
				state <= RX_STATE_START;
				data <= scratch;
				rdy <= 1'b1;
				sample <= 0;
			end else begin
				sample <= sample + 1;
			end
		end
		default: begin
			state <= RX_STATE_START;
		end
		endcase
	end
end

endmodule
