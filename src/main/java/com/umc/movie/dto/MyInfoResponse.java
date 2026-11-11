package com.umc.movie.dto;

import com.umc.movie.entity.Member;

import java.time.LocalDateTime;

public record MyInfoResponse(
        String email,
        String nickname,
        LocalDateTime createdAt
) {
    public static MyInfoResponse from(Member member) {
        return new MyInfoResponse(member.getEmail(), member.getNickname(), member.getCreatedAt());
    }
}
