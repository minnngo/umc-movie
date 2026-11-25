package com.umc.movie.controller;

import java.util.Map;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * ALB 타겟 그룹이 10초마다 찌르는 헬스 체크 엔드포인트입니다.
 * 스프링 컨텍스트(DB 커넥션 풀 포함)가 다 뜬 뒤에야 200 을 돌려주므로,
 * 이 응답이 오면 트래픽을 받아도 된다는 뜻입니다.
 */
@RestController
public class HealthController {

    @GetMapping("/health")
    public Map<String, String> health() {
        return Map.of("status", "ok");
    }
}
