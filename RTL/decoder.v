`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2023/08/02 00:13:57
// Design Name: 
// Module Name: decoder
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module decoder #(
    parameter OUTPUT_W    = 4,
    parameter COEFF_W     = 23,
    parameter W           = 64
) (
    input                               rst,
    input                               clk,
    input       [2:0]                   sec_lvl,
    input       [2:0]                   encode_modei,
    input                               valid_i,
    output reg                          ready_i,
    input       [W-1:0]                 di,
    output reg  [OUTPUT_W*COEFF_W-1:0]  samples,
    output reg                          valid_o,
    input                               ready_o
);

localparam      DILITHIUM_Q = 23'd8380417;
localparam      ENCODE_T0   = 3'd0;
localparam      ENCODE_T1   = 3'd1;
localparam      ENCODE_S1   = 3'd2;
localparam      ENCODE_S2   = 3'd3;
localparam      ENCODE_W1   = 3'd4;
localparam      ENCODE_Z    = 3'd5;
 
localparam      GAMMA1_2    = 23'd131072;
localparam      GAMMA1_35   = 23'd524288;
    
reg     [           3:0]    ETA;
reg     [           5:0]    ENCODE_LVL;

reg     [         W-1:0]    di_buffer;

reg     [           2:0]    encode_mode;
reg     [       3*W-1:0]    SIPO_IN;
reg     [       3*W-1:0]    SIPO_IN_SHIFT;
reg     [         199:0]    SIPO_OUT;
reg     [ 4*COEFF_W-1:0]    sipo_out_in;
reg     [ 4*COEFF_W-1:0]    sipo_out_in_shift;

reg     [           8:0]    sipo_in_len;
reg     [           8:0]    sipo_in_len_next;
reg     [           7:0]    sipo_out_len;
reg     [           7:0]    sipo_out_len_next;

reg     [       2*W-1:0]    di_shift;

integer i;
    
// dslee    00:28:35 2023-08-02
// "initial ?" non-sense.
//    initial begin
//        SIPO_IN  = 0;
//        SIPO_OUT = 0;
//    
//        sipo_in_len  = 0;
//        sipo_out_len = 0;
//    end


//------------------------------------------------------------
// constant
//------------------------------------------------------------
// ETA
always @(*) begin   : blk_ETA
    ETA = 0;
    
    casex({sec_lvl, encode_mode})
        {3'd2, ENCODE_S2},
        {3'd5, ENCODE_S2},
        {3'd2, ENCODE_S1},
        {3'd5, ENCODE_S1}: begin
            ETA = 2;
        end
        {3'd3, ENCODE_S2},
        {3'd3, ENCODE_S1}: begin
            ETA        = 4;
        end   
    endcase
end

// ENCODE_LVL
always @(*) begin   : blk_ENCODE_LVL
    ENCODE_LVL = 0;
    
    casex({sec_lvl, encode_mode})
        {3'dX, ENCODE_T0}: begin
            ENCODE_LVL = 13;
        end
        {3'dX, ENCODE_T1}: begin
            ENCODE_LVL = 10;
        end
        {3'd2, ENCODE_S2},
        {3'd5, ENCODE_S2},
        {3'd2, ENCODE_S1},
        {3'd5, ENCODE_S1}: begin
            ENCODE_LVL = 3;
        end
        {3'd3, ENCODE_S2},
        {3'd3, ENCODE_S1}: begin
            ENCODE_LVL = 4;
        end   
        {3'd3, ENCODE_W1},
        {3'd5, ENCODE_W1}: begin
            ENCODE_LVL = 4;
        end
        {3'd2, ENCODE_W1}: begin
            ENCODE_LVL = 6;
        end
        {3'd2, ENCODE_Z}: begin
            ENCODE_LVL = 18;
        end
        {3'd3, ENCODE_Z},
        {3'd5, ENCODE_Z}: begin
            ENCODE_LVL = 20;
        end
    endcase
end




//------------------------------------------------------------
// I/O control
//------------------------------------------------------------
// valid_o
always @(*) begin    
    valid_o = (sipo_out_len >= OUTPUT_W*COEFF_W) ? 1 : 0; 
end

// ready_i
always @(*) begin    
    ready_i = (sipo_in_len < 4*ENCODE_LVL || (valid_o && 4*ENCODE_LVL > 63)) ? 1 : 0;
end

    
// encode_mode
always @(posedge clk) begin
    // dslee    00:23:34 2023-08-02 without reset branch ... fine.
    encode_mode <= encode_modei;
end




//------------------------------------------------------------
// SIPO_IN
//------------------------------------------------------------
always @(*) begin    
    sipo_in_len_next  = (ready_i && valid_i) ? sipo_in_len + W : sipo_in_len;
end
always @(posedge clk or posedge rst) begin : blk_sipo_in_len
    if (rst) begin
        sipo_in_len  <= 0;
    end
    else begin
        if (sipo_out_len_next <= OUTPUT_W*COEFF_W) begin
            if (sipo_in_len >= 4*ENCODE_LVL) begin
                sipo_in_len  <= sipo_in_len_next  - 4*ENCODE_LVL;
            end
            else begin
                sipo_in_len  <= sipo_in_len_next;
            end
        end
        else begin
            sipo_in_len  <= sipo_in_len_next;
        end
    end 
end

always @(*) begin    : blk_di_shift
    if (sipo_in_len >= 4*ENCODE_LVL) begin
        di_shift = ({64'd0, di} << (sipo_in_len - 4*ENCODE_LVL));
    end else begin
        di_shift = ({64'd0, di} << sipo_in_len);
    end
end
always @(*) begin   : blk_SIPO_IN_SHIFT
    SIPO_IN_SHIFT = (SIPO_IN >> 4*ENCODE_LVL);
end

//always @(posedge clk) begin // dslee    00:21:23 2023-08-02 synchronous reset is OK, but I prefer async.
always @(posedge clk or posedge rst) begin : blk_SIPO_IN
    if (rst) begin
        SIPO_IN  <= 0;
    end
    else begin
        if (sipo_out_len_next <= OUTPUT_W*COEFF_W) begin
            if (sipo_in_len >= 4*ENCODE_LVL) begin
                if (valid_i) begin
                    SIPO_IN <= SIPO_IN_SHIFT | di_shift;
                end
                else begin
                    SIPO_IN <= SIPO_IN_SHIFT;
                end
            end
            else begin
                if (valid_i) begin
                    SIPO_IN <= SIPO_IN | di_shift;
                end
                else begin
                    SIPO_IN <= SIPO_IN;
                end
            end
        end
    end 
end




//------------------------------------------------------------
// SIPO_OUT
//------------------------------------------------------------
always @(*) begin   : blk_sipo_out_len_next
    sipo_out_len_next = (valid_o && ready_o) ? sipo_out_len - OUTPUT_W*COEFF_W: sipo_out_len;   
end
always @(posedge clk or posedge rst) begin : blk_sipo_out_len
    if (rst) begin
        sipo_out_len <= 0;  
    end
    else begin
        if (sipo_out_len_next <= OUTPUT_W*COEFF_W) begin
            if (sipo_in_len >= 4*ENCODE_LVL) begin
                sipo_out_len <= sipo_out_len_next + 4*COEFF_W;
            end
            else begin
                sipo_out_len <= sipo_out_len_next;
            end
        end
        else begin
            sipo_out_len <= sipo_out_len_next;
        end
    end 
end

always @(*) begin    : blk_sipo_out_in
    for (i = 0; i < 4; i = i + 1)
        sipo_out_in[i*COEFF_W+:COEFF_W] = 0;
    
    casex({sec_lvl, encode_mode})
        {3'dX, ENCODE_T0}: begin
            for (i = 0; i < 4; i = i + 1)
                sipo_out_in[i*COEFF_W+:COEFF_W] =  (SIPO_IN[i*13+:13] > 4096) ? DILITHIUM_Q - SIPO_IN[i*13+:13] + 4096 : 4096 - SIPO_IN[i*13+:13];
        end
        {3'dX, ENCODE_T1}: begin
            for (i = 0; i < 4; i = i + 1)
                sipo_out_in[i*COEFF_W+:COEFF_W] = {SIPO_IN[i*10+:10], 13'd0};
        end
        {3'd2, ENCODE_S2},
        {3'd5, ENCODE_S2},
        {3'd2, ENCODE_S1},
        {3'd5, ENCODE_S1}: begin
            for (i = 0; i < 4; i = i + 1)
                sipo_out_in[i*COEFF_W+:COEFF_W] = (SIPO_IN[i*3+:3] > ETA) ? DILITHIUM_Q - SIPO_IN[i*3+:3] + ETA : ETA - SIPO_IN[i*3+:3];
        end
        {3'd3, ENCODE_S2},
        {3'd3, ENCODE_S1}: begin
            for (i = 0; i < 4; i = i + 1)
                sipo_out_in[i*COEFF_W+:COEFF_W] = (SIPO_IN[i*4+:4] > ETA) ? DILITHIUM_Q - SIPO_IN[i*4+:4] + ETA : ETA - SIPO_IN[i*4+:4];
        end   
        {3'd3, ENCODE_W1},
        {3'd5, ENCODE_W1}: begin
            for (i = 0; i < 4; i = i + 1)
                sipo_out_in[i*COEFF_W+:COEFF_W] = SIPO_IN[i*4+:4];
        end
        {3'd2, ENCODE_W1}: begin
            for (i = 0; i < 4; i = i + 1)
                sipo_out_in[i*COEFF_W+:COEFF_W] = SIPO_IN[i*6+:6];
        end
        {3'd2, ENCODE_Z}: begin
            for (i = 0; i < 4; i = i + 1) begin
                if (sipo_in_len >= (i+1)*18)
                    sipo_out_in[i*COEFF_W+:COEFF_W] = (SIPO_IN[i*18+:18] > GAMMA1_2) ? GAMMA1_2 + (DILITHIUM_Q - SIPO_IN[i*18+:18]) : GAMMA1_2 - SIPO_IN[i*18+:18];
            end
        end
        {3'd3, ENCODE_Z},
        {3'd5, ENCODE_Z}: begin
            for (i = 0; i < 4; i = i + 1) begin
                if (sipo_in_len >= (i+1)*20)
                    sipo_out_in[i*COEFF_W+:COEFF_W] = (SIPO_IN[i*20+:20] > GAMMA1_35) ? GAMMA1_35 + DILITHIUM_Q - SIPO_IN[i*20+:20] : GAMMA1_35 - SIPO_IN[i*20+:20];
            end
        end
    endcase
end
always @(*) begin    : blk_sipo_out_in_shift
    if (valid_o && ready_o) begin   
        sipo_out_in_shift = sipo_out_in << (sipo_out_len - OUTPUT_W*COEFF_W);  
    end else begin
        sipo_out_in_shift = sipo_out_in << sipo_out_len;
    end
end

always @(posedge clk or posedge rst) begin : blk_SIPO_OUT
    if (rst) begin
        SIPO_OUT <= 0;
    end
    else begin
        if (valid_o && ready_o) begin   
            if (sipo_in_len >= ENCODE_LVL) begin
                SIPO_OUT <= (SIPO_OUT >> OUTPUT_W*COEFF_W) | sipo_out_in_shift;  
            end
            else begin
                SIPO_OUT <= SIPO_OUT >> OUTPUT_W*COEFF_W;
            end
        end
        else if (sipo_in_len >= ENCODE_LVL) begin
            SIPO_OUT <= SIPO_OUT | sipo_out_in_shift;
        end
    end 
end

// samples
always @(*) begin   : blk_samples
    samples = SIPO_OUT[OUTPUT_W*COEFF_W-1:0];
end
    
endmodule
