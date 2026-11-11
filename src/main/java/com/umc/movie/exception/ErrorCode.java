package com.umc.movie.exception;

import lombok.Getter;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;

// 화면이 오류 이유를 구분할 수 있도록 상황마다 다른 code와 message를 둡니다.
@Getter
@RequiredArgsConstructor
public enum ErrorCode {
    MEMBER_EMAIL_DUPLICATED(HttpStatus.CONFLICT, "MEMBER4091", "이미 사용 중인 이메일입니다."),
    MEMBER_NICKNAME_DUPLICATED(HttpStatus.CONFLICT, "MEMBER4092", "이미 사용 중인 닉네임입니다."),
    MEMBER_NOT_FOUND(HttpStatus.NOT_FOUND, "MEMBER4041", "존재하지 않는 유저입니다."),

    // 이메일이 없는지, 비밀번호가 틀렸는지 알려주지 않도록 같은 메시지를 씁니다.
    LOGIN_FAILED(HttpStatus.UNAUTHORIZED, "AUTH4011", "이메일 또는 비밀번호가 올바르지 않습니다."),
    TOKEN_MISSING(HttpStatus.UNAUTHORIZED, "AUTH4012", "로그인이 필요합니다."),
    TOKEN_INVALID(HttpStatus.UNAUTHORIZED, "AUTH4013", "유효하지 않은 토큰입니다."),
    TOKEN_EXPIRED(HttpStatus.UNAUTHORIZED, "AUTH4014", "만료된 토큰입니다. 다시 로그인해주세요.");

    private final HttpStatus status;
    private final String code;
    private final String message;
}
