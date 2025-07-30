`timescale 1ns / 1ps

// ===== 서클 애니메이션이 추가된 FND 컨트롤러 모듈 =====
module fnd_controller(
    input clk,                  // 100MHz 시스템 클럭
    input reset,                // 리셋 신호
    input [13:0] input_data,    // 표시할 데이터 (0~9999)
    input idle_animation,       // IDLE 상태 애니메이션 활성화
    output [7:0] seg_data,      // 7-segment 패턴 출력 (a~g + dp)
    output [3:0] an             // 자릿수 선택 신호 (4개 디스플레이 중 1개씩 켜기)
    );

    // ===== 내부 연결 와이어 =====
    wire [1:0] w_sel;           // 현재 선택된 자릿수 (00, 01, 10, 11)
    wire [3:0] w_d1, w_d10, w_d100, w_d1000;  // 각 자릿수의 BCD 값 (0~9)
    
    // ===== 애니메이션 관련 신호 =====
    reg [25:0] animation_counter = 0;   // 애니메이션 속도 제어 (약 0.67초마다 변경)
    reg [2:0] animation_pattern = 0;    // 애니메이션 패턴 (0~5)
    reg [7:0] animation_seg_reg;        // 애니메이션 세그먼트 패턴
    reg [3:0] animation_an_reg;         // 애니메이션 자릿수 선택
    
    parameter ANIMATION_SPEED = 67_000_000; // 0.67초 (100MHz 기준)
 
    // ===== 자릿수 선택 모듈 =====
    fnd_digit_select u_fnd_digit_select(
        .clk(clk),
        .reset(reset),
        .sel(w_sel)             // 현재 선택된 자릿수 출력
    );

    // ===== 이진수 → BCD 변환 모듈 =====
    bin2bcd u_bin2bcd(
        .in_data(input_data),   // 입력: 14비트 이진수
        .d1(w_d1),              // 출력: 1의 자리
        .d10(w_d10),            // 출력: 10의 자리
        .d100(w_d100),          // 출력: 100의 자리
        .d1000(w_d1000)         // 출력: 1000의 자리
    );

    // ===== 일반 7-segment 디스플레이 제어 모듈 =====
    wire [7:0] normal_seg_data;
    wire [3:0] normal_an;
    
    fnd_display u_fnd_display(
        .digit_sel(w_sel),      // 현재 선택된 자릿수
        .d1(w_d1),              // 1의 자리 BCD
        .d10(w_d10),            // 10의 자리 BCD
        .d100(w_d100),          // 100의 자리 BCD
        .d1000(w_d1000),        // 1000의 자리 BCD
        .an(normal_an),         // 자릿수 선택 출력
        .seg(normal_seg_data)   // 7-segment 패턴 출력
    );
    
    // ===== 애니메이션 카운터 및 패턴 생성 =====
    always @(posedge clk, posedge reset) begin
        if (reset) begin
            animation_counter <= 0;
            animation_pattern <= 0;
        end else if (idle_animation) begin
            if (animation_counter < ANIMATION_SPEED - 1) begin
                animation_counter <= animation_counter + 1;
            end else begin
                animation_counter <= 0;
                // 애니메이션 패턴 순환 (0→1→2→3→4→5→0...)
                if (animation_pattern < 5) begin
                    animation_pattern <= animation_pattern + 1;
                end else begin
                    animation_pattern <= 0;
                end
            end
        end else begin
            animation_counter <= 0;
            animation_pattern <= 0;
        end
    end
    
    // ===== 서클 애니메이션 세그먼트 패턴 생성 =====
    always @(*) begin
        // 기본값 설정
        animation_seg_reg = 8'b11111111;  // 모든 세그먼트 꺼짐
        animation_an_reg = 4'b1111;       // 모든 자릿수 비활성화
        
        // IDLE 상태일 때만 서클 애니메이션 활성화
        if (idle_animation) begin
            // 외곽 세그먼트를 시계방향으로 회전 (a→b→c→d→e→f)
            // 7-segment 패턴: {dp, g, f, e, d, c, b, a} (Common Anode, 0=켜짐)
            case (animation_pattern)
                3'd0: animation_seg_reg = 8'b11111110;  // a 세그먼트만 켜기
                3'd1: animation_seg_reg = 8'b11111101;  // b 세그먼트만 켜기  
                3'd2: animation_seg_reg = 8'b11111011;  // c 세그먼트만 켜기
                3'd3: animation_seg_reg = 8'b11110111;  // d 세그먼트만 켜기
                3'd4: animation_seg_reg = 8'b11101111;  // e 세그먼트만 켜기
                3'd5: animation_seg_reg = 8'b11011111;  // f 세그먼트만 켜기
                default: animation_seg_reg = 8'b11111111; // 예상외 값일 때 모든 세그먼트 꺼짐
            endcase
            
            // 모든 자릿수를 동시에 켜서 전체 디스플레이에 애니메이션 표시
            animation_an_reg = 4'b0000;  // 모든 자릿수 활성화 (0=켜짐)
        end
    end
    
    // ===== 출력 선택 (애니메이션 vs 일반 표시) =====
    assign seg_data = idle_animation ? animation_seg_reg : normal_seg_data;
    assign an = idle_animation ? animation_an_reg : normal_an;
    
endmodule

// ===== 자릿수 선택 모듈 =====
module fnd_digit_select(
    input clk,                  // 100MHz 클럭
    input reset,                // 리셋 신호
    output reg [1:0] sel        // 선택된 자릿수 (00, 01, 10, 11)
    );

    reg [16:0] r_1ms_counter = 0;   // 1ms 카운터 (100,000 클럭)
    reg [1:0] r_digit_sel = 0;      // 내부 자릿수 선택 신호
    
    always @(posedge clk, posedge reset) begin
        if (reset) begin
            r_1ms_counter <= 0;
            r_digit_sel <= 0;
            sel <= 0;
        end else begin
            // 1ms가 지나면 다음 자릿수로 이동
            if (r_1ms_counter == 100_000 - 1) begin // 1ms (100MHz 기준)
                r_1ms_counter <= 0;
                r_digit_sel <= r_digit_sel + 1;    // 00 → 01 → 10 → 11 → 00...
                sel <= r_digit_sel;
            end else begin
                r_1ms_counter <= r_1ms_counter + 1;
            end
        end
    end
endmodule

// ===== 이진수 → BCD 변환 모듈 =====
module bin2bcd(
    input [13:0] in_data,       // 입력: 14비트 이진수
    output [3:0] d1,            // 출력: 1의 자리 (0~9)
    output [3:0] d10,           // 출력: 10의 자리 (0~9)
    output [3:0] d100,          // 출력: 100의 자리 (0~9)
    output [3:0] d1000          // 출력: 1000의 자리 (0~9)
);
    // 각 자릿수 추출 (나머지 연산 사용)
    assign d1 = in_data % 10;           // 1의 자리: 입력 % 10
    assign d10 = (in_data / 10) % 10;   // 10의 자리: (입력 / 10) % 10
    assign d100 = (in_data / 100) % 10; // 100의 자리: (입력 / 100) % 10
    assign d1000 = (in_data / 1000) % 10; // 1000의 자리: (입력 / 1000) % 10

endmodule

// ===== 7-segment 디스플레이 제어 모듈 =====
module fnd_display(
    input [1:0] digit_sel,      // 현재 선택된 자릿수
    input [3:0] d1,             // 1의 자리 BCD
    input [3:0] d10,            // 10의 자리 BCD
    input [3:0] d100,           // 100의 자리 BCD
    input [3:0] d1000,          // 1000의 자리 BCD
    output reg [3:0] an,        // 자릿수 선택 출력 (0=켜짐, 1=꺼짐)
    output reg [7:0] seg        // 7-segment 패턴 (0=켜짐, 1=꺼짐)
);

    reg [3:0] bcd_data;         // 현재 표시할 BCD 데이터

    // ===== 자릿수 선택 및 데이터 선택 =====
    always @(*) begin
        case (digit_sel)
            2'b00: begin bcd_data = d1; an = 4'b1110; end      // 1의 자리 선택
            2'b01: begin bcd_data = d10; an = 4'b1101; end     // 10의 자리 선택
            2'b10: begin bcd_data = d100; an = 4'b1011; end    // 100의 자리 선택
            2'b11: begin bcd_data = d1000; an = 4'b0111; end   // 1000의 자리 선택
            default: begin bcd_data = 4'b0000; an = 4'b1111; end // 모두 꺼짐
        endcase
    end

    // ===== BCD → 7-segment 패턴 변환 =====
    always @(*) begin
        case (bcd_data)
            4'd0: seg = 8'b11000000;    // 0: abcdef 켜짐
            4'd1: seg = 8'b11111001;    // 1: bc 켜짐
            4'd2: seg = 8'b10100100;    // 2: abdeg 켜짐
            4'd3: seg = 8'b10110000;    // 3: abcdg 켜짐
            4'd4: seg = 8'b10011001;    // 4: bcfg 켜짐
            4'd5: seg = 8'b10010010;    // 5: acdfg 켜짐
            4'd6: seg = 8'b10000010;    // 6: acdefg 켜짐
            4'd7: seg = 8'b11111000;    // 7: abc 켜짐
            4'd8: seg = 8'b10000000;    // 8: abcdefg 켜짐
            4'd9: seg = 8'b10010000;    // 9: abcdfg 켜짐
            default: seg = 8'b11111111; // 모든 세그먼트 꺼짐
        endcase
    end
endmodule