`timescale 1ns / 1ps

// 부저 제어 모듈
module buzzer_controller(
    input clk,              // 100MHz 클럭
    input reset,            // 리셋 신호
    input button_pressed,   // 버튼 눌림 신호 (짧은 비프음)
    input completion_alarm, // 완료 알림 신호 (긴 알림음)
    output reg buzzer       // 부저 출력
);

    // 주파수 설정 (100MHz 기준)
    // 버튼음: 1000Hz = 50,000 카운트로 토글
    // 완료음: 800Hz = 62,500 카운트로 토글
    parameter BUTTON_FREQ_COUNT = 50_000;   // 1000Hz
    parameter ALARM_FREQ_COUNT = 62_500;    // 800Hz
    
    // 지속 시간 설정 (100MHz 기준)
    parameter BUTTON_DURATION = 10_000_000;  // 0.1초
    parameter ALARM_DURATION = 100_000_000;  // 1초
    
    reg [15:0] freq_counter = 0;
    reg [26:0] duration_counter = 0;
    reg [15:0] current_freq_count = 0;
    reg [26:0] current_duration = 0;
    reg buzzer_active = 0;
    reg buzzer_tone = 0;
    
    // 부저 활성화 및 주파수/지속시간 설정
    always @(posedge clk, posedge reset) begin
        if (reset) begin
            buzzer_active <= 0;
            current_freq_count <= 0;
            current_duration <= 0;
            duration_counter <= 0;
        end else begin
            // 버튼 눌림 감지
            if (button_pressed && !buzzer_active) begin
                buzzer_active <= 1;
                current_freq_count <= BUTTON_FREQ_COUNT;
                current_duration <= BUTTON_DURATION;
                duration_counter <= 0;
            end
            // 완료 알림 감지
            else if (completion_alarm && !buzzer_active) begin
                buzzer_active <= 1;
                current_freq_count <= ALARM_FREQ_COUNT;
                current_duration <= ALARM_DURATION;
                duration_counter <= 0;
            end
            // 부저 활성화 중일 때 지속시간 카운트
            else if (buzzer_active) begin
                if (duration_counter < current_duration - 1) begin
                    duration_counter <= duration_counter + 1;
                end else begin
                    buzzer_active <= 0;  // 지속시간 끝나면 비활성화
                    duration_counter <= 0;
                end
            end
        end
    end
    
    // 주파수 생성
    always @(posedge clk, posedge reset) begin
        if (reset) begin
            freq_counter <= 0;
            buzzer_tone <= 0;
        end else if (buzzer_active) begin
            if (freq_counter < current_freq_count - 1) begin
                freq_counter <= freq_counter + 1;
            end else begin
                freq_counter <= 0;
                buzzer_tone <= ~buzzer_tone;  // 주파수에 따라 토글
            end
        end else begin
            freq_counter <= 0;
            buzzer_tone <= 0;
        end
    end
    
    // 최종 부저 출력
    always @(*) begin
        buzzer = buzzer_active ? buzzer_tone : 1'b0;
    end

endmodule