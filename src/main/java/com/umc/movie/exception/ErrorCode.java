package com.umc.movie.exception;

import lombok.Getter;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;

// 화면이 오류 이유를 구분할 수 있도록 상황마다 다른 code와 message를 둡니다.
@Getter
@RequiredArgsConstructor
public enum ErrorCode {
    MEMBER_EMAIL_DUPLICATED(HttpStatus.CONFLICT, "MEMBER4091", "이미 사용 중인 이메일입니다."),
    MEMBER_NICKNAME_DUPLICATED(HttpStatus.CONFLICT, "MEMBER4092", "이미 사용 중인 닉네임입니다.");

    private final HttpStatus status;
    private final String code;
    private final String message;
}
