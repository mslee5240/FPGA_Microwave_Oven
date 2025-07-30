`timescale 1ns / 1ps

//==============================================================================
// 전자레인지 타이머 관리 모듈
// 기능: 시간 설정, 카운트다운, 타이머 상태 제어
// 특징: 듀얼 클럭 도메인 (100MHz 제어 + 1Hz 타이밍)
//==============================================================================
module timer_manager(
    input clk,              // 100MHz 시스템 클럭 (제어 로직용)
    input clk_1hz,          // 1Hz 클럭 (1초 카운트다운용)
    input reset,            // 전체 리셋
    
    // ===== 시간 설정 명령 =====
    input add_10sec,        // 10초 추가 요청
    input add_1min,         // 1분(60초) 추가 요청
    input set_30sec,        // 30초 퀵스타트 설정
    
    // ===== 타이머 제어 명령 =====
    input start_timer,      // 타이머 시작 (설정시간 → 남은시간 복사)
    input pause_timer,      // 일시정지 (카운트다운 중단)
    input resume_timer,     // 재시작 (일시정지 → 실행)
    input clear_timer,      // 초기화 (모든 시간과 상태 리셋)
    
    // ===== 타이머 상태 출력 =====
    output reg [11:0] set_time_sec,     // 사용자가 설정한 시간 (0~3600초)
    output reg [11:0] remaining_sec,    // 실제 카운트다운되는 남은 시간
    output reg timer_running,           // 실행 중 플래그 (카운트다운 활성)
    output reg timer_paused,            // 일시정지 플래그
    output reg timer_completed          // 완료 플래그 (0초 도달)
);

    parameter MAX_TIME = 3600;          // 최대 설정 시간: 60분 = 3600초
    
    // 타이머 활성화 상태 (시작 후 완료까지의 전체 기간)
    reg timer_active = 0;
    
    //==========================================================================
    // 클럭 도메인 크로싱 - 1Hz 신호를 100MHz 도메인에서 에지 검출
    //==========================================================================
    reg clk_1hz_prev = 0;                           // 1Hz 클럭 이전 상태 저장
    wire second_pulse = clk_1hz & ~clk_1hz_prev;    // 상승 에지 = 1초 펄스
    
    // 1Hz 클럭의 상승 에지 검출 (100MHz 도메인에서 동기화)
    always @(posedge clk, posedge reset) begin
        if (reset) begin
            clk_1hz_prev <= 0;
        end else begin
            clk_1hz_prev <= clk_1hz;           // 매 클럭마다 이전 상태 업데이트
        end
    end
    
    //==========================================================================
    // 시간 설정 로직 - 사용자 입력에 따른 설정 시간 변경
    //==========================================================================
    always @(posedge clk, posedge reset) begin
        if (reset || clear_timer) begin
            set_time_sec <= 0;                 // 리셋 시 설정 시간 초기화
        end else begin
            // 10초 추가 (오버플로우 방지: 3600초 초과 금지)
            if (add_10sec && (set_time_sec + 10 <= MAX_TIME)) begin
                set_time_sec <= set_time_sec + 10;
            end
            // 1분 추가 (오버플로우 방지)
            else if (add_1min && (set_time_sec + 60 <= MAX_TIME)) begin
                set_time_sec <= set_time_sec + 60;
            end
            // 퀵스타트: 30초로 즉시 설정
            else if (set_30sec) begin
                set_time_sec <= 30;
            end
        end
    end
    
    //==========================================================================
    // 타이머 제어 및 카운트다운 로직 - 메인 상태 머신
    //==========================================================================
    always @(posedge clk, posedge reset) begin
        if (reset || clear_timer) begin
            // 전체 초기화: 모든 상태와 시간을 리셋
            remaining_sec <= 0;
            timer_running <= 0;
            timer_paused <= 0;
            timer_completed <= 0;
            timer_active <= 0;
        end else begin
            
            // === 타이머 시작: 설정된 시간으로 카운트다운 시작 ===
            if (start_timer && set_time_sec > 0 && !timer_active) begin
                remaining_sec <= set_time_sec;      // 설정시간을 남은시간에 복사
                timer_running <= 1;                 // 실행 상태 활성화
                timer_paused <= 0;
                timer_completed <= 0;
                timer_active <= 1;                  // 타이머 활성화 (완료까지 유지)
            end
            
            // === 일시정지: 카운트다운 중단 (문 열림 또는 사용자 요청) ===
            else if (pause_timer && timer_running) begin
                timer_running <= 0;                 // 카운트다운 중단
                timer_paused <= 1;                  // 일시정지 상태 표시
            end
            
            // === 재시작: 일시정지에서 카운트다운 재개 ===
            else if (resume_timer && timer_paused) begin
                timer_running <= 1;                 // 카운트다운 재개
                timer_paused <= 0;                  // 일시정지 해제
            end
            
            // === 카운트다운: 1초마다 남은 시간 감소 ===
            else if (second_pulse && timer_running) begin
                if (remaining_sec > 0) begin
                    remaining_sec <= remaining_sec - 1;     // 1초 감소
                end else begin
                    // 타이머 완료 (0초 도달)
                    timer_running <= 0;
                    timer_paused <= 0;
                    timer_completed <= 1;           // 완료 상태 활성화
                    timer_active <= 0;              // 타이머 비활성화
                end
            end
            
            // === 일시정지 중 시간 추가: 남은 시간에 즉시 반영 ===
            else if (timer_paused) begin
                if (add_10sec && (remaining_sec + 10 <= MAX_TIME)) begin
                    remaining_sec <= remaining_sec + 10;    // 남은시간에 10초 추가
                end else if (add_1min && (remaining_sec + 60 <= MAX_TIME)) begin
                    remaining_sec <= remaining_sec + 60;    // 남은시간에 1분 추가
                end
            end
        end
    end

    //==========================================================================
    // 타이머 상태 요약:
    // - IDLE: timer_active=0, 시간 설정만 가능
    // - RUNNING: timer_running=1, 1초마다 카운트다운
    // - PAUSED: timer_paused=1, 카운트다운 중단, 시간 추가 가능
    // - COMPLETED: timer_completed=1, 알림 후 IDLE로 복귀
    //==========================================================================

endmodule