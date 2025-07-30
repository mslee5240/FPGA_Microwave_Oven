`timescale 1ns / 1ps

// 디버깅 기능이 추가된 SG90 서보모터 제어 모듈
module servo_controller(
    input clk,              // 100MHz 클럭
    input reset,            // 리셋 신호
    input door_toggle,      // 문 열기/닫기 토글 신호
    output reg servo,       // 서보모터 PWM 출력
    output reg door_open    // 문 상태 (1: 열림, 0: 닫힘)
);

    // 서보모터 PWM 주기 = 20ms = 2,000,000 클럭 (100MHz 기준)
    parameter PWM_PERIOD = 2_000_000;
    
    // 펄스 폭 설정 (100MHz 기준)
    // 0도 (문 닫힘): 1ms = 100,000 클럭
    // 90도 (문 열림): 1.5ms = 150,000 클럭
    parameter PULSE_0_DEG = 50_000;    // 모터 오차에 따라 0.5ms로 수정
    parameter PULSE_90_DEG = 250_000; // 180도임, 2.5ms
    
    reg [20:0] pwm_counter = 0;         // PWM 카운터
    reg [17:0] pulse_width = PULSE_0_DEG; // 현재 펄스 폭
    
    // door_toggle 신호 디바운싱 및 에지 검출
    reg door_toggle_prev = 0;
    reg door_toggle_stable = 0;
    reg [15:0] toggle_counter = 0;
    wire door_toggle_edge = door_toggle_stable & ~door_toggle_prev;
    
    // door_toggle 신호 안정화 (작은 디바운싱)
    always @(posedge clk, posedge reset) begin
        if (reset) begin
            door_toggle_stable <= 0;
            toggle_counter <= 0;
        end else begin
            if (door_toggle == door_toggle_stable) begin
                toggle_counter <= 0;
            end else begin
                toggle_counter <= toggle_counter + 1;
                if (toggle_counter == 16'hFFFF) begin  // 약 650us
                    door_toggle_stable <= door_toggle;
                    toggle_counter <= 0;
                end
            end
        end
    end
    
    // 에지 검출을 위한 이전 값 저장
    always @(posedge clk, posedge reset) begin
        if (reset) begin
            door_toggle_prev <= 0;
        end else begin
            door_toggle_prev <= door_toggle_stable;
        end
    end
    
    // 문 상태 토글 처리 - 수정된 로직
    always @(posedge clk, posedge reset) begin
        if (reset) begin
            door_open <= 0;
            pulse_width <= PULSE_0_DEG;  // 초기에는 문 닫힘
        end else if (door_toggle_edge) begin  // 에지 검출로 토글
            door_open <= ~door_open;
            
            // 토글 후의 상태에 따라 펄스 폭 설정
            if (door_open == 0) begin  // 현재 닫힘 -> 열림으로 변경 예정
                pulse_width <= PULSE_90_DEG;
            end else begin             // 현재 열림 -> 닫힘으로 변경 예정
                pulse_width <= PULSE_0_DEG;
            end
        end
    end
    
    // PWM 신호 생성
    always @(posedge clk, posedge reset) begin
        if (reset) begin
            pwm_counter <= 0;
            servo <= 0;
        end else begin
            if (pwm_counter < PWM_PERIOD - 1) begin
                pwm_counter <= pwm_counter + 1;
            end else begin
                pwm_counter <= 0;
            end
            
            // 펄스 폭 동안 HIGH, 나머지는 LOW
            servo <= (pwm_counter < pulse_width) ? 1'b1 : 1'b0;
        end
    end

endmodule