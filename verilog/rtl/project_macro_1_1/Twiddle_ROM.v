module Twiddle_ROM #(
    parameter DATA_WIDTH = 12,
    parameter ADDR_WIDTH = 8
)(
    input  wire mode,
    input  wire [6:0] addr,   
    output reg  [DATA_WIDTH-1:0] twiddle
);

    wire [7:0] full_addr = {mode, addr};

    always @(*) begin
        case (full_addr)

            // FORWARD TWIDDLES (mode = 0) -> Addresses 0 to 127

           8'd0  : twiddle = 12'd1   ;  8'd1  : twiddle = 12'd1729;  8'd2  : twiddle = 12'd2580;  8'd3  : twiddle = 12'd3289;
8'd4  : twiddle = 12'd2642;  8'd5  : twiddle = 12'd630 ;  8'd6  : twiddle = 12'd1897;  8'd7  : twiddle = 12'd848 ;
8'd8  : twiddle = 12'd1062;  8'd9  : twiddle = 12'd1919;  8'd10 : twiddle = 12'd193 ;  8'd11 : twiddle = 12'd797 ;
8'd12 : twiddle = 12'd2786;  8'd13 : twiddle = 12'd3260;  8'd14 : twiddle = 12'd569 ;  8'd15 : twiddle = 12'd1746;
8'd16 : twiddle = 12'd296 ;  8'd17 : twiddle = 12'd2447;  8'd18 : twiddle = 12'd1339;  8'd19 : twiddle = 12'd1476;
8'd20 : twiddle = 12'd3046;  8'd21 : twiddle = 12'd56  ;  8'd22 : twiddle = 12'd2240;  8'd23 : twiddle = 12'd1333;
8'd24 : twiddle = 12'd1426;  8'd25 : twiddle = 12'd2094;  8'd26 : twiddle = 12'd535 ;  8'd27 : twiddle = 12'd2882;
8'd28 : twiddle = 12'd2393;  8'd29 : twiddle = 12'd2879;  8'd30 : twiddle = 12'd1974;  8'd31 : twiddle = 12'd821 ;
8'd32 : twiddle = 12'd289 ;  8'd33 : twiddle = 12'd331 ;  8'd34 : twiddle = 12'd3253;  8'd35 : twiddle = 12'd1756;
8'd36 : twiddle = 12'd1197;  8'd37 : twiddle = 12'd2304;  8'd38 : twiddle = 12'd2277;  8'd39 : twiddle = 12'd2055;
8'd40 : twiddle = 12'd650 ;  8'd41 : twiddle = 12'd1977;  8'd42 : twiddle = 12'd2513;  8'd43 : twiddle = 12'd632 ;
8'd44 : twiddle = 12'd2865;  8'd45 : twiddle = 12'd33  ;  8'd46 : twiddle = 12'd1320;  8'd47 : twiddle = 12'd1915;
8'd48 : twiddle = 12'd2319;  8'd49 : twiddle = 12'd1435;  8'd50 : twiddle = 12'd807 ;  8'd51 : twiddle = 12'd452 ;
8'd52 : twiddle = 12'd1438;  8'd53 : twiddle = 12'd2868;  8'd54 : twiddle = 12'd1534;  8'd55 : twiddle = 12'd2402;
8'd56 : twiddle = 12'd2647;  8'd57 : twiddle = 12'd2617;  8'd58 : twiddle = 12'd1481;  8'd59 : twiddle = 12'd648 ;
8'd60 : twiddle = 12'd2474;  8'd61 : twiddle = 12'd3110;  8'd62 : twiddle = 12'd1227;  8'd63 : twiddle = 12'd910 ;
8'd64 : twiddle = 12'd17  ;  8'd65 : twiddle = 12'd2761;  8'd66 : twiddle = 12'd583 ;  8'd67 : twiddle = 12'd2649;
8'd68 : twiddle = 12'd1637;  8'd69 : twiddle = 12'd723 ;  8'd70 : twiddle = 12'd2288;  8'd71 : twiddle = 12'd1100;
8'd72 : twiddle = 12'd1409;  8'd73 : twiddle = 12'd2662;  8'd74 : twiddle = 12'd3281;  8'd75 : twiddle = 12'd233 ;
8'd76 : twiddle = 12'd756 ;  8'd77 : twiddle = 12'd2156;  8'd78 : twiddle = 12'd3015;  8'd79 : twiddle = 12'd3050;
8'd80 : twiddle = 12'd1703;  8'd81 : twiddle = 12'd1651;  8'd82 : twiddle = 12'd2789;  8'd83 : twiddle = 12'd1789;
8'd84 : twiddle = 12'd1847;  8'd85 : twiddle = 12'd952 ;  8'd86 : twiddle = 12'd1461;  8'd87 : twiddle = 12'd2687;
8'd88 : twiddle = 12'd939 ;  8'd89 : twiddle = 12'd2308;  8'd90 : twiddle = 12'd2437;  8'd91 : twiddle = 12'd2388;
8'd92 : twiddle = 12'd733 ;  8'd93 : twiddle = 12'd2337;  8'd94 : twiddle = 12'd268 ;  8'd95 : twiddle = 12'd641 ;
8'd96 : twiddle = 12'd1584;  8'd97 : twiddle = 12'd2298;  8'd98 : twiddle = 12'd2037;  8'd99 : twiddle = 12'd3220;
8'd100: twiddle = 12'd375 ;  8'd101: twiddle = 12'd2549;  8'd102: twiddle = 12'd2090;  8'd103: twiddle = 12'd1645;
8'd104: twiddle = 12'd1063;  8'd105: twiddle = 12'd319 ;  8'd106: twiddle = 12'd2773;  8'd107: twiddle = 12'd757 ;
8'd108: twiddle = 12'd2099;  8'd109: twiddle = 12'd561 ;  8'd110: twiddle = 12'd2466;  8'd111: twiddle = 12'd2594;
8'd112: twiddle = 12'd2804;  8'd113: twiddle = 12'd1092;  8'd114: twiddle = 12'd403 ;  8'd115: twiddle = 12'd1026;
8'd116: twiddle = 12'd1143;  8'd117: twiddle = 12'd2150;  8'd118: twiddle = 12'd2775;  8'd119: twiddle = 12'd886 ;
8'd120: twiddle = 12'd1722;  8'd121: twiddle = 12'd1212;  8'd122: twiddle = 12'd1874;  8'd123: twiddle = 12'd1029;
8'd124: twiddle = 12'd2110;  8'd125: twiddle = 12'd2935;  8'd126: twiddle = 12'd885 ;  8'd127: twiddle = 12'd2154;

// INVERSE TWIDDLES (mode = 1) -> Addresses 128 to 255

8'd128: twiddle = 12'd3040;  8'd129: twiddle = 12'd1175;  8'd130: twiddle = 12'd2444;  8'd131: twiddle = 12'd394 ;
8'd132: twiddle = 12'd1219;  8'd133: twiddle = 12'd2300;  8'd134: twiddle = 12'd1455;  8'd135: twiddle = 12'd2117;
8'd136: twiddle = 12'd1607;  8'd137: twiddle = 12'd2443;  8'd138: twiddle = 12'd554 ;  8'd139: twiddle = 12'd1179;
8'd140: twiddle = 12'd2186;  8'd141: twiddle = 12'd2303;  8'd142: twiddle = 12'd2926;  8'd143: twiddle = 12'd2237;
8'd144: twiddle = 12'd525 ;  8'd145: twiddle = 12'd735 ;  8'd146: twiddle = 12'd863 ;  8'd147: twiddle = 12'd2768;
8'd148: twiddle = 12'd1230;  8'd149: twiddle = 12'd2572;  8'd150: twiddle = 12'd556 ;  8'd151: twiddle = 12'd3010;
8'd152: twiddle = 12'd2266;  8'd153: twiddle = 12'd1684;  8'd154: twiddle = 12'd1239;  8'd155: twiddle = 12'd780 ;
8'd156: twiddle = 12'd2954;  8'd157: twiddle = 12'd109 ;  8'd158: twiddle = 12'd1292;  8'd159: twiddle = 12'd1031;
8'd160: twiddle = 12'd1745;  8'd161: twiddle = 12'd2688;  8'd162: twiddle = 12'd3061;  8'd163: twiddle = 12'd992 ;
8'd164: twiddle = 12'd2596;  8'd165: twiddle = 12'd941 ;  8'd166: twiddle = 12'd892 ;  8'd167: twiddle = 12'd1021;
8'd168: twiddle = 12'd2390;  8'd169: twiddle = 12'd642 ;  8'd170: twiddle = 12'd1868;  8'd171: twiddle = 12'd2377;
8'd172: twiddle = 12'd1482;  8'd173: twiddle = 12'd1540;  8'd174: twiddle = 12'd540 ;  8'd175: twiddle = 12'd1678;
8'd176: twiddle = 12'd1626;  8'd177: twiddle = 12'd279 ;  8'd178: twiddle = 12'd314 ;  8'd179: twiddle = 12'd1173;
8'd180: twiddle = 12'd2573;  8'd181: twiddle = 12'd3096;  8'd182: twiddle = 12'd48  ;  8'd183: twiddle = 12'd667 ;
8'd184: twiddle = 12'd1920;  8'd185: twiddle = 12'd2229;  8'd186: twiddle = 12'd1041;  8'd187: twiddle = 12'd2606;
8'd188: twiddle = 12'd1692;  8'd189: twiddle = 12'd680 ;  8'd190: twiddle = 12'd2746;  8'd191: twiddle = 12'd568 ;
8'd192: twiddle = 12'd3033;  8'd193: twiddle = 12'd2419;  8'd194: twiddle = 12'd2102;  8'd195: twiddle = 12'd219 ;
8'd196: twiddle = 12'd855 ;  8'd197: twiddle = 12'd2681;  8'd198: twiddle = 12'd1848;  8'd199: twiddle = 12'd712 ;
8'd200: twiddle = 12'd682 ;  8'd201: twiddle = 12'd927 ;  8'd202: twiddle = 12'd1795;  8'd203: twiddle = 12'd461 ;
8'd204: twiddle = 12'd1891;  8'd205: twiddle = 12'd2877;  8'd206: twiddle = 12'd2522;  8'd207: twiddle = 12'd1894;
8'd208: twiddle = 12'd1010;  8'd209: twiddle = 12'd1414;  8'd210: twiddle = 12'd2009;  8'd211: twiddle = 12'd3296;
8'd212: twiddle = 12'd464 ;  8'd213: twiddle = 12'd2697;  8'd214: twiddle = 12'd816 ;  8'd215: twiddle = 12'd1352;
8'd216: twiddle = 12'd2679;  8'd217: twiddle = 12'd1274;  8'd218: twiddle = 12'd1052;  8'd219: twiddle = 12'd1025;
8'd220: twiddle = 12'd2132;  8'd221: twiddle = 12'd1573;  8'd222: twiddle = 12'd76  ;  8'd223: twiddle = 12'd2998;
8'd224: twiddle = 12'd2267;  8'd225: twiddle = 12'd2508;  8'd226: twiddle = 12'd1355;  8'd227: twiddle = 12'd450 ;
8'd228: twiddle = 12'd936 ;  8'd229: twiddle = 12'd447 ;  8'd230: twiddle = 12'd2794;  8'd231: twiddle = 12'd1235;
8'd232: twiddle = 12'd1903;  8'd233: twiddle = 12'd1996;  8'd234: twiddle = 12'd1089;  8'd235: twiddle = 12'd3273;
8'd236: twiddle = 12'd283 ;  8'd237: twiddle = 12'd1853;  8'd238: twiddle = 12'd1990;  8'd239: twiddle = 12'd882 ;
8'd240: twiddle = 12'd687 ;  8'd241: twiddle = 12'd1583;  8'd242: twiddle = 12'd2760;  8'd243: twiddle = 12'd69  ;
8'd244: twiddle = 12'd543 ;  8'd245: twiddle = 12'd2532;  8'd246: twiddle = 12'd3136;  8'd247: twiddle = 12'd1410;
8'd248: twiddle = 12'd749 ;  8'd249: twiddle = 12'd2481;  8'd250: twiddle = 12'd1432;  8'd251: twiddle = 12'd2699;
8'd252: twiddle = 12'd1600;  8'd253: twiddle = 12'd40  ;  8'd254: twiddle = 12'd1   ;  8'd255: twiddle = 12'd0   ;
            default: twiddle = 12'd0;
        endcase
    end

endmodule