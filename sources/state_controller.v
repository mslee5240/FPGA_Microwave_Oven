`timescale 1ns / 1ps

//==============================================================================
// 전자레인지 상태 제어 모듈 - 5상태 FSM 기반 메인 컨트롤러
// 기능: 사용자 입력 처리, 상태 전환, 하드웨어 제어 신호 생성
// 특징: 더블클릭 퀵스타트, 문 열림 감지, 완료 알림 제어
//==============================================================================
module state_controller(
    input clk,                  // 100MHz 시스템 클럭
    input clk_1hz,              // 1Hz 클럭 (사용하지 않음, 호환성용)
    input reset,                // 전체 리셋
    
    // ===== 사용자 버튼 입력 (디바운싱 완료된 신호) =====
    input btnC_pulse,           // 시작/일시정지/재시작 (다기능 버튼)
    input btnU_pulse,           // 10초 추가
    input btnR_pulse,           // 1분 추가  
    input btnL_stable,          // 문 토글 (stable 신호, 펄스 아님)
    input btnD_pulse,           // 취소/전체 리셋
    
    // ===== 시스템 상태 입력 =====
    input door_open,            // 문 열림 상태 (서보모터로부터)
    input timer_completed,      // 타이머 완료 신호 (타이머 매니저로부터)
    input [11:0] set_time_sec,  // 현재 설정된 시간 (초)
    input [11:0] remaining_sec, // 남은 시간 (초)
    
    // ===== 타이머 제어 출력 =====
    output reg add_10sec,       // 타이머에 10초 추가 명령
    output reg add_1min,        // 타이머에 1분 추가 명령
    output reg set_30sec,       // 30초 퀵스타트 설정 명령
    output reg start_timer,     // 타이머 시작 명령
    output reg pause_timer,     // 타이머 일시정지 명령
    output reg resume_timer,    // 타이머 재시작 명령
    output reg clear_timer,     // 타이머 전체 초기화 명령
    
    // ===== 하드웨어 제어 출력 =====
    output reg door_toggle,     // 서보모터 문 토글 신호
    output reg button_beep,     // 버튼 비프음 요청
    output reg completion_alarm,// 완료 알림음 요청
    output reg motor_enable,    // DC모터 (플레이트 회전) 활성화
    
    // ===== 디스플레이 제어 출력 =====
    output reg display_blink,   // 디스플레이 점멸 제어 (COMPLETE 상태용)
    output reg idle_animation,  // IDLE 상태 서클 애니메이션 활성화
    
    // ===== 상태 정보 출력 =====
    output reg [2:0] current_state,  // 현재 FSM 상태 (디버깅용)
    output reg [13:0] display_data   // 7-segment에 표시할 데이터
);

    //==========================================================================
    // FSM 상태 정의 - 전자레인지의 5가지 동작 상태
    //==========================================================================
    parameter IDLE = 3'b000;        // 대기: 시간 미설정, 애니메이션 표시
    parameter SETTING = 3'b001;     // 설정: 시간 설정 중
    parameter RUNNING = 3'b010;     // 작동: 가열 중, 모터 회전, 카운트다운
    parameter PAUSED = 3'b011;      // 일시정지: 문 열림 또는 사용자 요청
    parameter COMPLETE = 3'b100;    // 완료: 점멸 알림, 완료음
    
    reg [2:0] state = IDLE;         // 현재 상태
    reg [2:0] next_state;           // 다음 상태 (조합 로직)
    
    //==========================================================================
    // 더블클릭 감지 로직 - btnC 버튼의 30초 퀵스타트 기능
    //==========================================================================
    reg [25:0] btnC_timer = 0;      // 더블클릭 윈도우 타이머
    reg btnC_first_click = 0;       // 첫 번째 클릭 플래그
    reg btnC_double_click = 0;      // 더블클릭 감지 플래그
    parameter DOUBLE_CLICK_WINDOW = 50_000_000; // 0.5초 윈도우 (100MHz 기준)
    
    //==========================================================================
    // 문 버튼 에지 검출 - stable 신호에서 상승 에지 추출
    //==========================================================================
    reg btnL_prev = 0;              // btnL 이전 상태
    wire btnL_edge = btnL_stable & ~btnL_prev;  // 상승 에지 = 버튼 눌림 순간
    
    //==========================================================================
    // 완료 상태 점멸 제어 - 5회 점멸 후 자동 IDLE 복귀
    //==========================================================================
    reg [3:0] blink_count = 0;      // 점멸 횟수 (0~10, 5회 점멸 = 10번 토글)
    reg [25:0] blink_timer = 0;     // 점멸 주기 타이머
    reg blink_state = 0;            // 현재 점멸 상태 (0=꺼짐, 1=켜짐)
    reg completion_alarm_active = 0; // 완료 알림음 활성화 플래그
    parameter BLINK_PERIOD = 50_000_000; // 0.5초 점멸 주기
    parameter MAX_BLINKS = 10;      // 최대 점멸 횟수 (5회 깜빡임)
    
    //==========================================================================
    // 상태 레지스터 업데이트 및 에지 검출
    //==========================================================================
    always @(posedge clk, posedge reset) begin
        if (reset) begin
            state <= IDLE;              // 리셋 시 IDLE 상태로
            current_state <= IDLE;      // 출력용 상태도 동기화
            btnL_prev <= 0;             // 문 버튼 이전 상태 초기화
        end else begin
            state <= next_state;        // 다음 상태로 전환
            current_state <= next_state; // 외부 출력용
            btnL_prev <= btnL_stable;   // 문 버튼 에지 검출용 이전 값 저장
        end
    end
    
    //==========================================================================
    // 더블클릭 감지 로직 - 0.5초 내 두 번 클릭 시 퀵스타트
    //==========================================================================
    always @(posedge clk, posedge reset) begin
        if (reset) begin
            btnC_timer <= 0;
            btnC_first_click <= 0;
            btnC_double_click <= 0;
        end else begin
            btnC_double_click <= 0;     // 매 클럭마다 기본값으로 리셋
            
            // IDLE 상태에서 시간이 설정되지 않은 경우에만 더블클릭 감지
            if (btnC_pulse && state == IDLE && set_time_sec == 0) begin
                if (!btnC_first_click) begin
                    // 첫 번째 클릭: 타이머 시작
                    btnC_first_click <= 1;
                    btnC_timer <= 0;
                end else if (btnC_timer < DOUBLE_CLICK_WINDOW) begin
                    // 두 번째 클릭 (윈도우 내): 더블클릭 성공
                    btnC_double_click <= 1;
                    btnC_first_click <= 0;
                    btnC_timer <= 0;
                end
            end else if (btnC_first_click) begin
                // 첫 클릭 후 대기 중
                if (btnC_timer < DOUBLE_CLICK_WINDOW) begin
                    btnC_timer <= btnC_timer + 1;  // 윈도우 타이머 증가
                end else begin
                    // 윈도우 타임아웃: 싱글클릭으로 처리
                    btnC_first_click <= 0;
                    btnC_timer <= 0;
                end
            end
        end
    end
    
    //==========================================================================
    // 완료 상태 점멸 제어 - 0.5초 주기로 5회 점멸
    //==========================================================================
    always @(posedge clk, posedge reset) begin
        if (reset) begin
            blink_count <= 0;
            blink_timer <= 0;
            blink_state <= 0;
            completion_alarm_active <= 0;
        end else if (state == COMPLETE) begin
            if (blink_count < MAX_BLINKS) begin
                // 아직 점멸 중
                if (blink_timer < BLINK_PERIOD - 1) begin
                    blink_timer <= blink_timer + 1;    // 0.5초 타이머 증가
                end else begin
                    blink_timer <= 0;                  // 타이머 리셋
                    blink_state <= ~blink_state;       // 점멸 상태 토글
                    blink_count <= blink_count + 1;    // 점멸 횟수 증가
                    
                    // 첫 번째 토글에서 완료 알림음 시작
                    if (blink_count == 0) begin
                        completion_alarm_active <= 1;
                    end
                end
            end else begin
                // 점멸 완료: 알림음 중단
                completion_alarm_active <= 0;
            end
        end else begin
            // COMPLETE 상태가 아닐 때: 모든 점멸 관련 신호 초기화
            blink_count <= 0;
            blink_timer <= 0;
            blink_state <= 0;
            completion_alarm_active <= 0;
        end
    end
    
    //==========================================================================
    // FSM 상태 전환 로직 - 입력 조건에 따른 다음 상태 결정
    //==========================================================================
    always @(*) begin
        next_state = state;         // 기본값: 현재 상태 유지
        
        case (state)
            IDLE: begin
                // 대기 상태: 시간 설정 또는 즉시 시작
                if (btnD_pulse) begin
                    next_state = IDLE;      // 취소 버튼: IDLE 유지
                end else if (btnU_pulse || btnR_pulse) begin
                    next_state = SETTING;   // 시간 추가: 설정 모드로
                end else if (btnC_pulse && set_time_sec == 0) begin
                    // 시간 미설정 시 btnC: 더블클릭이면 바로 실행, 아니면 설정
                    next_state = btnC_double_click ? RUNNING : SETTING;
                end else if (btnC_pulse && set_time_sec > 0 && !door_open) begin
                    next_state = RUNNING;   // 시간 설정됨 + 문 닫힘: 바로 실행
                end
            end
            
            SETTING: begin
                // 설정 상태: 시간 추가 가능, 시작 대기
                if (btnD_pulse) begin
                    next_state = IDLE;      // 취소: 초기화 후 IDLE
                end else if (btnC_pulse && set_time_sec > 0 && !door_open) begin
                    next_state = RUNNING;   // 시작: 실행 상태로
                end
            end
            
            RUNNING: begin
                // 실행 상태: 가열 중, 일시정지 가능
                if (btnD_pulse) begin
                    next_state = IDLE;      // 취소: 즉시 중단
                end else if (btnC_pulse || door_open) begin
                    next_state = PAUSED;    // 일시정지 또는 문 열림
                end else if (timer_completed) begin
                    next_state = COMPLETE;  // 타이머 완료: 알림 상태로
                end
            end
            
            PAUSED: begin
                // 일시정지 상태: 재시작 또는 취소 대기
                if (btnD_pulse) begin
                    next_state = IDLE;      // 취소: 중단 후 IDLE
                end else if (btnC_pulse && !door_open) begin
                    next_state = RUNNING;   // 재시작 (문이 닫혀있어야 함)
                end
            end
            
            COMPLETE: begin
                // 완료 상태: 점멸 후 자동 복귀 또는 수동 복귀
                if (btnD_pulse || (blink_count >= MAX_BLINKS)) begin
                    next_state = IDLE;      // 취소 또는 점멸 완료: IDLE로
                end
            end
            
            default: next_state = IDLE; // 예상외 상태: 안전하게 IDLE로
        endcase
    end
    
    //==========================================================================
    // 출력 신호 생성 - 상태와 버튼 입력에 따른 제어 신호 생성
    //==========================================================================
    always @(posedge clk, posedge reset) begin
        if (reset) begin
            // 리셋 시 모든 출력 초기화
            add_10sec <= 0; add_1min <= 0; set_30sec <= 0;
            start_timer <= 0; pause_timer <= 0; resume_timer <= 0; clear_timer <= 0;
            door_toggle <= 0; button_beep <= 0; completion_alarm <= 0;
            motor_enable <= 0; display_blink <= 1; idle_animation <= 0;
        end else begin
            // === 펄스 신호들 기본값으로 리셋 (1클럭만 활성화) ===
            add_10sec <= 0; add_1min <= 0; set_30sec <= 0;
            start_timer <= 0; pause_timer <= 0; resume_timer <= 0; clear_timer <= 0;
            door_toggle <= 0; button_beep <= 0; completion_alarm <= 0;
            
            // === 상태 기반 지속 신호들 ===
            display_blink <= (state == COMPLETE) ? blink_state : 1'b1;  // 완료시 점멸
            motor_enable <= (state == RUNNING) ? 1'b1 : 1'b0;           // 실행시 모터 on
            idle_animation <= (state == IDLE && set_time_sec == 0) ? 1'b1 : 1'b0; // IDLE+시간미설정시 애니메이션
            completion_alarm <= completion_alarm_active;                 // 완료 알림음
            
            // === 개별 버튼 처리 ===
            
            // 10초 추가 버튼 (btnU)
            if (btnU_pulse) begin
                button_beep <= 1;           // 버튼음 재생
                if (state == SETTING || state == PAUSED) begin
                    add_10sec <= 1;         // 설정/일시정지 중에만 시간 추가
                end
            end
            
            // 1분 추가 버튼 (btnR)
            if (btnR_pulse) begin
                button_beep <= 1;
                if (state == SETTING || state == PAUSED) begin
                    add_1min <= 1;
                end
            end
            
            // 문 토글 버튼 (btnL) - stable 신호를 직접 서보에 전달
            door_toggle <= btnL_stable;     // 실시간 문 제어
            if (btnL_stable) begin
                button_beep <= 1;           // 문 조작시 버튼음
            end
            
            // 취소 버튼 (btnD)
            if (btnD_pulse) begin
                button_beep <= 1;
                clear_timer <= 1;           // 타이머 전체 초기화
            end
            
            // 시작/일시정지 버튼 (btnC) - 상태별 다른 동작
            if (btnC_pulse) begin
                button_beep <= 1;
                case (state)
                    IDLE: begin
                        if (set_time_sec == 0) begin
                            set_30sec <= 1;        // 시간 미설정: 30초 설정
                            if (btnC_double_click) begin
                                start_timer <= 1;   // 더블클릭: 즉시 시작
                            end
                        end else if (!door_open) begin
                            start_timer <= 1;      // 시간 설정됨: 시작
                        end
                    end
                    SETTING: begin
                        if (set_time_sec > 0 && !door_open) begin
                            start_timer <= 1;      // 설정 완료: 시작
                        end
                    end
                    RUNNING: begin
                        pause_timer <= 1;          // 실행 중: 일시정지
                    end
                    PAUSED: begin
                        if (!door_open) begin
                            resume_timer <= 1;     // 일시정지: 재시작 (문 닫힘 확인)
                        end
                    end
                endcase
            end
            
            // === 문 열림 자동 감지 ===
            if (state == RUNNING && door_open) begin
                pause_timer <= 1;               // 실행 중 문 열림: 자동 일시정지
            end
        end
    end
    
    //==========================================================================
    // 디스플레이 데이터 생성 - 상태별 표시 내용 결정
    //==========================================================================
    always @(*) begin
        case (state)
            IDLE:    display_data = 14'd0;          // "0000" - 대기 상태
            SETTING: display_data = set_time_sec;   // 설정 중인 시간 표시
            RUNNING, PAUSED: display_data = remaining_sec; // 남은 시간 표시
            COMPLETE: display_data = 14'd0;         // "0000" - 완료 상태
            default: display_data = 14'd0;          // 안전값
        endcase
    end

    //==========================================================================
    // FSM 동작 요약:
    // IDLE → SETTING: 시간 추가 버튼
    // SETTING → RUNNING: 시작 버튼 (문 닫힘 확인)
    // RUNNING → PAUSED: 일시정지 버튼 또는 문 열림
    // PAUSED → RUNNING: 재시작 버튼 (문 닫힘 확인)
    // RUNNING → COMPLETE: 타이머 완료
    // COMPLETE → IDLE: 5회 점멸 완료 또는 취소 버튼
    //==========================================================================

endmodule