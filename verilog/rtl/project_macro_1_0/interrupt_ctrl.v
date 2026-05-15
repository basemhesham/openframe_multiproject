module interrupt_ctrl #(
    parameter NUM_IRQ = 8
) (
    input wire clk,
    input wire rst_n,
    input wire [NUM_IRQ-1:0] ext_irq,
    input wire [NUM_IRQ-1:0] fast_mask,
    output reg irq_pending,
    output reg fast_irq,
    output reg [2:0] irq_index
);
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            irq_pending <= 1'b0;
            fast_irq <= 1'b0;
            irq_index <= 3'd0;
        end else begin
            irq_pending <= 1'b0;
            fast_irq <= 1'b0;
            irq_index <= 3'd0;
            for (i = 0; i < NUM_IRQ; i = i + 1) begin
                if (ext_irq[i] && !irq_pending) begin
                    irq_pending <= 1'b1;
                    fast_irq <= fast_mask[i];
                    irq_index <= i[2:0];
                end
            end
        end
    end
endmodule
