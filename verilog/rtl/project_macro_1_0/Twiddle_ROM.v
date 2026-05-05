module Twiddle_ROM #(
    parameter DATA_WIDTH = 12,
    parameter ADDR_WIDTH = 7 
)(
    input  wire [ADDR_WIDTH-1:0] addr,
    output reg  [DATA_WIDTH-1:0] twiddle
);

    always @(*) begin
        case (addr)
            7'd0: twiddle = 12'd1;     7'd1: twiddle = 12'd1729;  7'd2: twiddle = 12'd2580;  7'd3: twiddle = 12'd3289;
            7'd4: twiddle = 12'd2642;  7'd5: twiddle = 12'd630;   7'd6: twiddle = 12'd3312;  7'd7: twiddle = 12'd2771;
            7'd8:  twiddle = 12'd136;  7'd9:  twiddle = 12'd153;  7'd10: twiddle = 12'd170;  7'd11: twiddle = 12'd187;
            7'd12: twiddle = 12'd204;  7'd13: twiddle = 12'd221;  7'd14: twiddle = 12'd238;  7'd15: twiddle = 12'd255;
            7'd16: twiddle = 12'd272;  7'd17: twiddle = 12'd289;  7'd18: twiddle = 12'd306;  7'd19: twiddle = 12'd323;
            7'd20: twiddle = 12'd340;  7'd21: twiddle = 12'd357;  7'd22: twiddle = 12'd374;  7'd23: twiddle = 12'd391;
            7'd24: twiddle = 12'd408;  7'd25: twiddle = 12'd425;  7'd26: twiddle = 12'd442;  7'd27: twiddle = 12'd459;
            7'd28: twiddle = 12'd476;  7'd29: twiddle = 12'd493;  7'd30: twiddle = 12'd510;  7'd31: twiddle = 12'd527;
            7'd32: twiddle = 12'd544;  7'd33: twiddle = 12'd561;  7'd34: twiddle = 12'd578;  7'd35: twiddle = 12'd595;
            7'd36: twiddle = 12'd612;  7'd37: twiddle = 12'd629;  7'd38: twiddle = 12'd646;  7'd39: twiddle = 12'd663;
            7'd40: twiddle = 12'd680;  7'd41: twiddle = 12'd697;  7'd42: twiddle = 12'd714;  7'd43: twiddle = 12'd731;
            7'd44: twiddle = 12'd748;  7'd45: twiddle = 12'd765;  7'd46: twiddle = 12'd782;  7'd47: twiddle = 12'd799;
            7'd48: twiddle = 12'd816;  7'd49: twiddle = 12'd833;  7'd50: twiddle = 12'd850;  7'd51: twiddle = 12'd867;
            7'd52: twiddle = 12'd884;  7'd53: twiddle = 12'd901;  7'd54: twiddle = 12'd918;  7'd55: twiddle = 12'd935;
            7'd56: twiddle = 12'd952;  7'd57: twiddle = 12'd969;  7'd58: twiddle = 12'd986;  7'd59: twiddle = 12'd1003;
            7'd60: twiddle = 12'd1020; 7'd61: twiddle = 12'd1037; 7'd62: twiddle = 12'd1054; 7'd63: twiddle = 12'd1071;
            7'd64: twiddle = 12'd1088; 7'd65: twiddle = 12'd1105; 7'd66: twiddle = 12'd1122; 7'd67: twiddle = 12'd1139;
            7'd68: twiddle = 12'd1156; 7'd69: twiddle = 12'd1173; 7'd70: twiddle = 12'd1190; 7'd71: twiddle = 12'd1207;
            7'd72: twiddle = 12'd1224; 7'd73: twiddle = 12'd1241; 7'd74: twiddle = 12'd1258; 7'd75: twiddle = 12'd1275;
            7'd76: twiddle = 12'd1292; 7'd77: twiddle = 12'd1309; 7'd78: twiddle = 12'd1326; 7'd79: twiddle = 12'd1343;
            7'd80: twiddle = 12'd1360; 7'd81: twiddle = 12'd1377; 7'd82: twiddle = 12'd1394; 7'd83: twiddle = 12'd1411;
            7'd84: twiddle = 12'd1428; 7'd85: twiddle = 12'd1445; 7'd86: twiddle = 12'd1462; 7'd87: twiddle = 12'd1479;
            7'd88: twiddle = 12'd1496; 7'd89: twiddle = 12'd1513; 7'd90: twiddle = 12'd1530; 7'd91: twiddle = 12'd1547;
            7'd92: twiddle = 12'd1564; 7'd93: twiddle = 12'd1581; 7'd94: twiddle = 12'd1598; 7'd95: twiddle = 12'd1615;
            7'd96: twiddle = 12'd1632; 7'd97: twiddle = 12'd1649; 7'd98: twiddle = 12'd1666; 7'd99: twiddle = 12'd1683;
            7'd100: twiddle = 12'd1700; 7'd101: twiddle = 12'd1717; 7'd102: twiddle = 12'd1734; 7'd103: twiddle = 12'd1751;
            7'd104: twiddle = 12'd1768; 7'd105: twiddle = 12'd1785; 7'd106: twiddle = 12'd1802; 7'd107: twiddle = 12'd1819;
            7'd108: twiddle = 12'd1836; 7'd109: twiddle = 12'd1853; 7'd110: twiddle = 12'd1870; 7'd111: twiddle = 12'd1887;
            7'd112: twiddle = 12'd1904; 7'd113: twiddle = 12'd1921; 7'd114: twiddle = 12'd1938; 7'd115: twiddle = 12'd1955;
            7'd116: twiddle = 12'd1972; 7'd117: twiddle = 12'd1989; 7'd118: twiddle = 12'd2006; 7'd119: twiddle = 12'd2023;
            7'd120: twiddle = 12'd2040; 7'd121: twiddle = 12'd2057; 7'd122: twiddle = 12'd2074; 7'd123: twiddle = 12'd2091;
            7'd124: twiddle = 12'd2108; 7'd125: twiddle = 12'd2125; 7'd126: twiddle = 12'd2142; 7'd127: twiddle = 12'd2159;
            default: twiddle = 12'd0;
        endcase
    end

endmodule