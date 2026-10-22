`default_nettype none

module aligator_video_timing #(

    parameter HVIS = 320,
    parameter HFP  = 8,
    parameter HSW  = 28,
    parameter HBP  = 28,

    parameter VVIS = 240,
    parameter VFP  = 10,
    parameter VSW  = 8,
    parameter VBP  = 6,
    parameter SYNC_ACTIVE = 1'b1

)(
    input  wire        clk,
    input  wire        rst,
    input  wire        ce_pix,
    input  wire        wide,       // TomSVR: 384 visible pixels in a 440-pixel line (Snow Board)

    output wire [9:0]  hpos,
    output wire [8:0]  vpos,
    output wire        frame_end,

    output reg         hsync,
    output reg         vsync,
    output reg         hblank,
    output reg         vblank,
    output wire        de,

    output reg         vblank_irq
);
    wire [9:0] HV = wide ? 10'd384 : HVIS;
    wire [9:0] HTOTAL = wide ? 10'd440 : HVIS + HFP + HSW + HBP;
    localparam VTOTAL = VVIS + VFP + VSW + VBP;

    reg [9:0] hcnt;
    reg [8:0] vcnt;

    wire hmax = (hcnt == HTOTAL-1);
    wire vmax = (vcnt == VTOTAL-1);
    assign frame_end = vmax;

`ifdef SIMULATION
    initial begin
        hcnt = 10'd0; vcnt = 9'd0;
        hsync = ~SYNC_ACTIVE; vsync = ~SYNC_ACTIVE;
        hblank = 1'b1; vblank = 1'b1; vblank_irq = 1'b0;
    end
`endif

    always @(posedge clk) begin
        if (ce_pix) begin
            vblank_irq <= 1'b0;

            if (hmax) begin
                hcnt <= 0;

                if (vmax) vcnt <= 0;
                else      vcnt <= vcnt + 1'b1;
            end else begin
                hcnt <= hcnt + 1'b1;
            end

            hblank <= (hcnt >= HV) ? 1'b1 : 1'b0;
            vblank <= (vcnt >= VVIS) ? 1'b1 : 1'b0;

            hsync <= (hcnt >= HV+HFP && hcnt < HV+HFP+HSW) ? SYNC_ACTIVE : ~SYNC_ACTIVE;
            vsync <= (vcnt >= VVIS+VFP && vcnt < VVIS+VFP+VSW) ? SYNC_ACTIVE : ~SYNC_ACTIVE;

            if (hmax && vcnt == VVIS-1) vblank_irq <= 1'b1;
        end
    end

    assign hpos = hcnt;
    assign vpos = vcnt[8:0];

    assign de   = (hcnt <= HV) && (vcnt < VVIS);

endmodule

`default_nettype wire
