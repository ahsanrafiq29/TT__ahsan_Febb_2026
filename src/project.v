/*
 * Copyright (c) 2024 Uri Shaked
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_vga_example(
  input  wire [7:0] ui_in,    // Dedicated inputs
  output wire [7:0] uo_out,   // Dedicated outputs
  input  wire [7:0] uio_in,   // IOs: Input path
  output wire [7:0] uio_out,  // IOs: Output path
  output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
  input  wire       ena,      // always 1 when the design is powered, so you can ignore it
  input  wire       clk,      // clock
  input  wire       rst_n     // reset_n - low to reset
);

  // VGA signals
  wire hsync;
  wire vsync;
  wire video_active;
  wire [9:0] pix_x;
  wire [9:0] pix_y;

  // 2-bit per channel color
  wire [1:0] R;
  wire [1:0] G;
  wire [1:0] B;

  // Keep same TinyVGA PMOD mapping as original
  assign uo_out = {hsync, B[0], G[0], R[0], vsync, B[0], G[0], R[0]};

  // Unused outputs assigned to 0.
  assign uio_out = 0;
  assign uio_oe  = 0;

  // Suppress unused signals warning
  wire _unused_ok = &{ena, ui_in, uio_in};

  // hvsync generator (same interface expected)
  hvsync_generator hvsync_gen(
    .clk(clk),
    .reset(~rst_n),
    .hsync(hsync),
    .vsync(vsync),
    .display_on(video_active),
    .hpos(pix_x),
    .vpos(pix_y)
  );

  // vsync-based counter to animate petal pulsation
  reg [7:0] vsync_counter;
  always @(posedge vsync or negedge rst_n) begin
    if (~rst_n) vsync_counter <= 0;
    else vsync_counter <= vsync_counter + 1;
  end

  // --- Flower geometry parameters (tuned for 640x480 active area) ---
  localparam integer CX = 320;                 // center x
  localparam integer CY = 240;                 // center y
  localparam integer CENTER_R2 = 16*16;        // center circle radius^2
  localparam integer PETAL_R2_BASE = 28*28;    // base petal radius^2
  localparam integer PETAL_DIST = 48;          // distance from center to petal center

  // signed deltas (enough width for products)
  wire signed [11:0] dx = $signed({1'b0, pix_x}) - $signed(CX);
  wire signed [11:0] dy = $signed({1'b0, pix_y}) - $signed(CY);

  // squared distance to center
  wire [23:0] dist2_center = $unsigned(dx * dx) + $unsigned(dy * dy);

  // small pulsate factor from vsync_counter (0..15 used)
  wire [3:0] scale = vsync_counter[3:0];
  wire [23:0] petal_r2 = PETAL_R2_BASE + (PETAL_R2_BASE * $unsigned(scale) / 8);

  // six petals around the center (approximate trig using integer offsets)
  localparam integer D = PETAL_DIST;
  localparam integer SEV = (D * 7) / 8; // approx 0.875*D

  // petal center offsets (signed)
  wire signed [11:0] pet_cx0 = D;    wire signed [11:0] pet_cy0 = 0;
  wire signed [11:0] pet_cx1 = D/2;  wire signed [11:0] pet_cy1 = SEV;
  wire signed [11:0] pet_cx2 = -D/2; wire signed [11:0] pet_cy2 = SEV;
  wire signed [11:0] pet_cx3 = -D;   wire signed [11:0] pet_cy3 = 0;
  wire signed [11:0] pet_cx4 = -D/2; wire signed [11:0] pet_cy4 = -SEV;
  wire signed [11:0] pet_cx5 = D/2;  wire signed [11:0] pet_cy5 = -SEV;

  // offsets from pixel to each petal center
  wire signed [11:0] dx0 = dx - pet_cx0; wire signed [11:0] dy0 = dy - pet_cy0;
  wire signed [11:0] dx1 = dx - pet_cx1; wire signed [11:0] dy1 = dy - pet_cy1;
  wire signed [11:0] dx2 = dx - pet_cx2; wire signed [11:0] dy2 = dy - pet_cy2;
  wire signed [11:0] dx3 = dx - pet_cx3; wire signed [11:0] dy3 = dy - pet_cy3;
  wire signed [11:0] dx4 = dx - pet_cx4; wire signed [11:0] dy4 = dy - pet_cy4;
  wire signed [11:0] dx5 = dx - pet_cx5; wire signed [11:0] dy5 = dy - pet_cy5;

  // squared distances to petal centers
  wire [23:0] d2_0 = $unsigned(dx0*dx0) + $unsigned(dy0*dy0);
  wire [23:0] d2_1 = $unsigned(dx1*dx1) + $unsigned(dy1*dy1);
  wire [23:0] d2_2 = $unsigned(dx2*dx2) + $unsigned(dy2*dy2);
  wire [23:0] d2_3 = $unsigned(dx3*dx3) + $unsigned(dy3*dy3);
  wire [23:0] d2_4 = $unsigned(dx4*dx4) + $unsigned(dy4*dy4);
  wire [23:0] d2_5 = $unsigned(dx5*dx5) + $unsigned(dy5*dy5);

  // pixel is in a petal if within any petal radius
  wire petal_here = (d2_0 < petal_r2) |
                    (d2_1 < petal_r2) |
                    (d2_2 < petal_r2) |
                    (d2_3 < petal_r2) |
                    (d2_4 < petal_r2) |
                    (d2_5 < petal_r2);

  // center small circle
  wire center_here = (dist2_center < CENTER_R2);

  // simple sky gradient background using pix_y bits
  wire [1:0] sky_blue = pix_y[8:7];

  // Color mapping (2-bit channels). Masked by video_active (black when inactive).
  // center: bright yellow (R=3,G=3,B=0)
  // petals: magenta-ish (R=3,G=1,B=2)
  // background: sky_blue gradient
  assign R = video_active ? (center_here ? 2'b11 : (petal_here ? 2'b11 : sky_blue)) : 2'b00;
  assign G = video_active ? (center_here ? 2'b11 : (petal_here ? 2'b01 : 2'b00)) : 2'b00;
  assign B = video_active ? (center_here ? 2'b00 : (petal_here ? 2'b10 : sky_blue)) : 2'b00;

endmodule
