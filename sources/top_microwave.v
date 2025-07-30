`timescale 1ns / 1ps

//==============================================================================
// 전자레인지 최상위 제어 모듈
// 기능: 5상태 FSM 기반 타이머, 하드웨어 제어, 사용자 인터페이스
//==============================================================================
module top_microwave(
    input clk,              // 100MHz 시스템 클럭
    input reset,            // 전체 시스템 리셋 (스위치 0번)
    
    // ===== 사용자 입력 인터페이스 =====
    input btnC,             // 시작/일시정지/재시작 버튼
    input btnU,             // 10초 추가 버튼
    input btnR,             // 1분 추가 버튼
    input btnL,             // 문 열기/닫기 토글 버튼
    input btnD,             // 취소/리셋 버튼
    
    // ===== 디스플레이 출력 =====
    output [7:0] seg,       // 7-segment 패턴 출력 (시간 표시)
    output [3:0] an,        // 7-segment 자릿수 선택
    
    // ===== 하드웨어 제어 출력 =====
    output PWM_OUT,         // DC 모터 PWM (플레이트 회전)
    output [1:0] in1_in2,   // DC 모터 방향 제어
    output servo,           // 서보 모터 PWM (문 개폐)
    output buzzer,          // 부저 출력 (버튼음/완료음)
    
    // ===== 디버깅 인터페이스 =====
    output [15:0] led       // 상태 표시용 LED
);

    //==========================================================================
    // 내부 신호 선언 - 모듈 간 통신용 와이어
    //==========================================================================
    
    // 클럭 관련
    wire w_clk_1hz;                         // 1Hz 분주 클럭 (타이머용)
    
    // 버튼 디바운싱 출력 (stable: 안정화, pulse: 1클럭 펄스)
    wire w_btnC_stable, w_btnC_pulse;       // 시작/정지 버튼
    wire w_btnU_stable, w_btnU_pulse;       // 10초 추가 버튼
    wire w_btnR_stable, w_btnR_pulse;       // 1분 추가 버튼
    wire w_btnL_stable, w_btnL_pulse;       // 문 토글 버튼
    wire w_btnD_stable, w_btnD_pulse;       // 취소 버튼
    
    // 상태 제어기 → 타이머 제어 신호
    wire w_add_10sec, w_add_1min, w_set_30sec;      // 시간 설정 명령
    wire w_start_timer, w_pause_timer, w_resume_timer, w_clear_timer; // 타이머 제어
    
    // 상태 제어기 → 하드웨어 제어 신호
    wire w_door_toggle;                     // 문 토글 신호
    wire w_button_beep, w_completion_alarm; // 소리 제어
    wire w_motor_enable;                    // 모터 활성화
    wire w_display_blink, w_idle_animation; // 디스플레이 효과
    
    // 상태 정보
    wire [2:0] w_current_state;             // 현재 FSM 상태
    wire [13:0] w_display_data;             // 디스플레이 표시 데이터
    
    // 타이머 상태 정보
    wire [11:0] w_set_time_sec, w_remaining_sec;    // 설정/남은 시간 (초)
    wire w_timer_running, w_timer_paused, w_timer_completed; // 타이머 상태
    
    // 하드웨어 피드백
    wire w_door_open;                       // 문 열림 상태 (서보모터 → 상태제어)

    //==========================================================================
    // 클럭 분주 - 100MHz를 1Hz로 변환 (정확한 1초 타이머용)
    //==========================================================================
    clock_divider u_clock_divider(
        .clk(clk),
        .reset(reset),
        .clk_1hz(w_clk_1hz)                 // 1초마다 펄스 생성
    );
    
    //==========================================================================
    // 버튼 디바운싱 - 기계적 바운싱 제거 (10ms 안정화)
    //==========================================================================
    // 시작/일시정지 버튼 (더블클릭 감지용으로도 사용)
    my_button_debounce u_btnC_debounce(
        .i_clk(clk), .i_reset(reset), .i_btn(btnC),
        .o_btn_stable(w_btnC_stable), .o_btn_pulse(w_btnC_pulse)
    );
    
    // 10초 추가 버튼
    my_button_debounce u_btnU_debounce(
        .i_clk(clk), .i_reset(reset), .i_btn(btnU),
        .o_btn_stable(w_btnU_stable), .o_btn_pulse(w_btnU_pulse)
    );
    
    // 1분 추가 버튼
    my_button_debounce u_btnR_debounce(
        .i_clk(clk), .i_reset(reset), .i_btn(btnR),
        .o_btn_stable(w_btnR_stable), .o_btn_pulse(w_btnR_pulse)
    );
    
    // 문 토글 버튼 (stable 신호를 직접 서보 제어에 사용)
    my_button_debounce u_btnL_debounce(
        .i_clk(clk), .i_reset(reset), .i_btn(btnL),
        .o_btn_stable(w_btnL_stable), .o_btn_pulse(w_btnL_pulse)
    );
    
    // 취소/리셋 버튼
    my_button_debounce u_btnD_debounce(
        .i_clk(clk), .i_reset(reset), .i_btn(btnD),
        .o_btn_stable(w_btnD_stable), .o_btn_pulse(w_btnD_pulse)
    );
    
    //==========================================================================
    // 타이머 관리 - 시간 설정, 카운트다운, 타이머 상태 관리
    //==========================================================================
    timer_manager u_timer_manager(
        .clk(clk), .clk_1hz(w_clk_1hz), .reset(reset),
        
        // 시간 설정 입력
        .add_10sec(w_add_10sec), .add_1min(w_add_1min), .set_30sec(w_set_30sec),
        
        // 타이머 제어 입력
        .start_timer(w_start_timer), .pause_timer(w_pause_timer),
        .resume_timer(w_resume_timer), .clear_timer(w_clear_timer),
        
        // 타이머 상태 출력
        .set_time_sec(w_set_time_sec), .remaining_sec(w_remaining_sec),
        .timer_running(w_timer_running), .timer_paused(w_timer_paused),
        .timer_completed(w_timer_completed)
    );
    
    //==========================================================================
    // 상태 제어기 - 5상태 FSM (IDLE/SETTING/RUNNING/PAUSED/COMPLETE)
    // 사용자 입력을 받아 타이머와 하드웨어를 제어
    //==========================================================================
    state_controller u_state_controller(
        .clk(clk), .clk_1hz(w_clk_1hz), .reset(reset),
        
        // 버튼 입력 (디바운싱된 신호)
        .btnC_pulse(w_btnC_pulse), .btnU_pulse(w_btnU_pulse),
        .btnR_pulse(w_btnR_pulse), .btnL_stable(w_btnL_stable),
        .btnD_pulse(w_btnD_pulse),
        
        // 시스템 상태 입력
        .door_open(w_door_open), .timer_completed(w_timer_completed),
        .set_time_sec(w_set_time_sec), .remaining_sec(w_remaining_sec),
        
        // 타이머 제어 출력
        .add_10sec(w_add_10sec), .add_1min(w_add_1min), .set_30sec(w_set_30sec),
        .start_timer(w_start_timer), .pause_timer(w_pause_timer),
        .resume_timer(w_resume_timer), .clear_timer(w_clear_timer),
        
        // 하드웨어 제어 출력
        .door_toggle(w_door_toggle), .button_beep(w_button_beep),
        .completion_alarm(w_completion_alarm), .motor_enable(w_motor_enable),
        .display_blink(w_display_blink), .idle_animation(w_idle_animation),
        
        // 상태 정보 출력
        .current_state(w_current_state), .display_data(w_display_data)
    );
    
    //==========================================================================
    // 7-segment 디스플레이 제어 - 시간 표시 및 IDLE 애니메이션
    //==========================================================================
    // 점멸 효과: COMPLETE 상태에서 디스플레이를 깜빡이게 함
    wire [13:0] final_display_data;
    assign final_display_data = w_display_blink ? w_display_data : 14'd0;
    
    // FND 컨트롤러 (멀티플렉싱 + BCD 변환 + 애니메이션)
    fnd_controller u_fnd_controller(
        .clk(clk), .reset(reset),
        .input_data(final_display_data),        // 표시할 시간 데이터
        .idle_animation(w_idle_animation),      // IDLE 상태 서클 애니메이션
        .seg_data(seg), .an(an)                 // 7-segment 출력
    );
    
    //==========================================================================
    // 하드웨어 제어 모듈들
    //==========================================================================
    
    // 서보 모터 - 문 자동 개폐 (0도: 닫힘, 90도: 열림)
    servo_controller u_servo_controller(
        .clk(clk), .reset(reset),
        .door_toggle(w_door_toggle),            // 문 토글 명령
        .servo(servo),                          // PWM 출력
        .door_open(w_door_open)                 // 문 상태 피드백
    );
    
    // 부저 제어 - 버튼음(1000Hz) 및 완료음(800Hz)
    buzzer_controller u_buzzer_controller(
        .clk(clk), .reset(reset),
        .button_pressed(w_button_beep),         // 버튼 소리 요청
        .completion_alarm(w_completion_alarm),  // 완료 알림 요청
        .buzzer(buzzer)                         // 부저 출력
    );
    
    // DC 모터 - 작동 중 플레이트 회전 (PWM 제어)
    simple_dcmotor u_simple_dcmotor(
        .clk(clk), .reset(reset),
        .motor_enable(w_motor_enable),          // 모터 활성화 신호
        .PWM_OUT(PWM_OUT), .in1_in2(in1_in2)   // PWM 및 방향 제어
    );
    
    //==========================================================================
    // 디버깅용 LED - 시스템 상태 실시간 모니터링
    //==========================================================================
    assign led[0] = w_btnL_stable;              // 문 버튼 상태
    assign led[1] = 1'b0;                       // 예약
    assign led[2] = w_door_toggle;              // 문 토글 신호
    assign led[3] = w_door_open;                // 문 열림 상태
    assign led[6:4] = w_current_state;          // FSM 상태 (3비트)
    assign led[7] = w_timer_running;            // 타이머 실행 상태
    assign led[8] = w_motor_enable;             // 모터 활성화 상태
    assign led[15:9] = w_remaining_sec[6:0];    // 남은 시간 (하위 7비트)

endmodule