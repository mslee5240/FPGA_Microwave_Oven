`timescale 1ns / 1ps

// 간단한 DC 모터 제어 모듈 (pwm_duty_cycle_control 로직 참고)
module simple_dcmotor(
    input clk,                  // 100MHz 클럭
    input reset,                // 리셋 신호
    input motor_enable,         // 모터 활성화 (1: 동작, 0: 정지)
    output PWM_OUT,             // PWM 출력
    output [1:0] in1_in2        // 모터 방향 제어
);

    // PWM 생성 로직 (pwm_duty_cycle_control 참고)
    reg [3:0] r_DUTY_CYCLE = 5;     // 듀티 사이클 (초기값 50%)
    reg [3:0] r_counter_PWM = 0;    // PWM 카운터 (0~9 반복)
    
    // motor_enable에 따른 듀티 사이클 제어
    always @(posedge clk, posedge reset) begin
        if (reset) begin
            r_DUTY_CYCLE <= 5;  // 리셋 시 50%로 초기화
        end else begin
            if (motor_enable) begin
                r_DUTY_CYCLE <= 4'd3;  // 최대 출력 (100%)
            end else begin
                r_DUTY_CYCLE <= 4'd0;   // 정지 (0%)
            end
        end
    end
    
    // PWM 카운터 (pwm_duty_cycle_control과 동일한 로직)
    always @(posedge clk, posedge reset) begin
        if (reset) begin
            r_counter_PWM <= 0;
        end else begin
            r_counter_PWM <= r_counter_PWM + 1;
            if (r_counter_PWM >= 9) begin
                r_counter_PWM <= 0;
            end
        end
    end
    
    // PWM 출력 생성 (pwm_duty_cycle_control과 동일한 로직)
    assign PWM_OUT = r_counter_PWM < r_DUTY_CYCLE ? 1'b1 : 1'b0;
    
    // 모터 방향 제어
    // motor_enable = 1: 정방향 회전 (in1=1, in2=0)
    // motor_enable = 0: 정지 (in1=0, in2=0)  
    assign in1_in2[0] = motor_enable ? 1'b1 : 1'b0;  // in1
    assign in1_in2[1] = 1'b0;                         // in2 (항상 0으로 정방향)

endmodule