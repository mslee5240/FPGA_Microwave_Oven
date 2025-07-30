`timescale 1ns / 1ps

// 카운터 기반 디바운싱 모듈
module my_button_debounce(
    input i_clk,                // 시스템 클럭 (100MHz)
    input i_reset,              // 비동기 리셋 (Acitve High)
    input i_btn,                // 디바운싱할 버튼 입력
    output reg o_btn_stable,    // 디바운싱된 안정된 버튼 신호
    output reg o_btn_pulse      // 버튼 눌림 순간의 1클럭 펄스 신호
);

    // 파라미터 및 내부 신호 선언
    // 디바운스 시간 설정 (100MHz 기준 10ms = 1,000,000 클럭)
    parameter DEBOUNCE_TIME = 1_000_000;

    // 디바운스 시간을 세는 카운터
    reg [$clog2(DEBOUNCE_TIME)-1:0] counter = 0;

    // 이전 클럭의 안정된 버튼 상태 저장 (펄스 생성용)
    reg btn_prev = 0;

    // 메인 로직: 클럭 상승엣지 또는 리셋 시 동작
    always @(posedge i_clk, posedge i_reset) begin
        // 리셋 처리: 모든 신호를 초기 상태로 설정
        if (i_reset) begin
            counter <= 0;       // 카운터 초기화
            btn_prev <= 0;      // 이전 상태 초기화
            o_btn_stable <= 0;  // 안정된 출력 초기화
            o_btn_pulse <= 0;   // 펄스 출력 초기화
        end

        // 정상 동작 모드
        else begin
            // 현재 안정된 상태를 이전 상태로 저장 (다음 클럭에서 사용)
            btn_prev <= o_btn_stable;

            // 디바운싱 로직
            // 경우 1: 버튼 입력이 현재 안정된 출력과 동일한 경우
            if (i_btn == o_btn_stable) begin
                // -> 상태가 안정되어 있으므로 카운터를 0으로 리셋
                counter <= 0;
            end 
            
            // 경우 2: 버튼 입력이 현재 안정된 출력과 다른 경우
            else begin
                // -> 상태 변화가 감지되었으므로 디바운스 시간 측정 시작

                // 디바운스 시간(10ms)이 완료된 경우
                if (counter == DEBOUNCE_TIME - 1) begin
                    o_btn_stable <= i_btn;  // 새로운 버튼 상태를 안정된 상태로 승인
                    counter <= 0;           // 카운터 리셋
                end 
                
                // 디바운스 시간이 아직 완료되지 않은 경우
                else begin
                    counter <= counter + 1; // 카운터 증가하여 시간 측정 계속
                end
            end

            // 펄스 신호 생성 (상승 엣지 검출)

            // 조건: 이전 상태가 0(버튼 안눌림) AND 현재 상태가 1(버튼 눌림)
            // -> 버튼이 눌린 순간에만 1클럭 동안 High 신호 생성
            o_btn_pulse <= (~btn_prev) & o_btn_stable;
        end
    end
endmodule
