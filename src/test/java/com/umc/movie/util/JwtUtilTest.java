package com.umc.movie.util;

import com.umc.movie.exception.ApiException;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class JwtUtilTest {

    private static final String SECRET = "test-secret-key-must-be-at-least-32-bytes!!";
    private final JwtUtil jwtUtil = new JwtUtil(SECRET, 3600L);

    @Test
    void 발급한_토큰에서_memberId를_꺼낸다() {
        String token = jwtUtil.createAccessToken(7L, "movie@umc.com");

        assertThat(token.split("\\.")).hasSize(3); // Header.Payload.Signature
        assertThat(jwtUtil.getMemberId(token)).isEqualTo(7L);
    }

    @Test
    void 다른_비밀키로_서명한_토큰은_거절한다() {
        JwtUtil otherServer = new JwtUtil("another-secret-key-also-32-bytes-long!!", 3600L);
        String forged = otherServer.createAccessToken(1L, "movie@umc.com");

        assertThatThrownBy(() -> jwtUtil.getMemberId(forged))
                .isInstanceOf(ApiException.class)
                .extracting(e -> ((ApiException) e).getCode())
                .isEqualTo("AUTH401_3");
    }

    @Test
    void 만료된_토큰은_거절한다() {
        // 60초 시계 오차를 허용하므로 그보다 더 오래전에 만료된 토큰을 만듭니다.
        JwtUtil expiredIssuer = new JwtUtil(SECRET, -120L);
        String expired = expiredIssuer.createAccessToken(1L, "movie@umc.com");

        assertThatThrownBy(() -> jwtUtil.getMemberId(expired))
                .isInstanceOf(ApiException.class)
                .extracting(e -> ((ApiException) e).getCode())
                .isEqualTo("AUTH401_4");
    }

    @Test
    void 형식이_잘못된_토큰은_거절한다() {
        assertThatThrownBy(() -> jwtUtil.getMemberId("not-a-jwt"))
                .isInstanceOf(ApiException.class)
                .extracting(e -> ((ApiException) e).getCode())
                .isEqualTo("AUTH401_3");
    }
}
