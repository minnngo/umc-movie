package com.umc.movie.auth;

import com.umc.movie.exception.ErrorCode;
import com.umc.movie.exception.GeneralException;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class JwtProviderTest {

    private static final String SECRET = "test-secret-key-must-be-at-least-32-bytes!!";
    private final JwtProvider jwtProvider = new JwtProvider(SECRET, 60);

    @Test
    void 발급한_토큰에서_memberId를_꺼낸다() {
        String token = jwtProvider.createAccessToken(7L);

        assertThat(token.split("\\.")).hasSize(3); // Header.Payload.Signature
        assertThat(jwtProvider.getMemberId(token)).isEqualTo(7L);
    }

    @Test
    void 서명이_다른_키로_만든_토큰은_거절한다() {
        JwtProvider otherServer = new JwtProvider("another-secret-key-also-32-bytes-long!!", 60);
        String forged = otherServer.createAccessToken(1L);

        assertThatThrownBy(() -> jwtProvider.getMemberId(forged))
                .isInstanceOf(GeneralException.class)
                .extracting(e -> ((GeneralException) e).getErrorCode())
                .isEqualTo(ErrorCode.TOKEN_INVALID);
    }

    @Test
    void 만료된_토큰은_거절한다() {
        JwtProvider expiredProvider = new JwtProvider(SECRET, -1);
        String expired = expiredProvider.createAccessToken(1L);

        assertThatThrownBy(() -> jwtProvider.getMemberId(expired))
                .isInstanceOf(GeneralException.class)
                .extracting(e -> ((GeneralException) e).getErrorCode())
                .isEqualTo(ErrorCode.TOKEN_EXPIRED);
    }

    @Test
    void 형식이_잘못된_토큰은_거절한다() {
        assertThatThrownBy(() -> jwtProvider.getMemberId("not-a-jwt"))
                .isInstanceOf(GeneralException.class)
                .extracting(e -> ((GeneralException) e).getErrorCode())
                .isEqualTo(ErrorCode.TOKEN_INVALID);
    }
}
