Shader "Unlit/08_RaymarchingWithUnityCamera"
{
    Properties
    {
        _BallAlbedo ("Ball Albedo", Color) = (1, 0, 0, 1)
        _FloorAlbedoA ("Floor Albedo A", Color) = (0, 0, 0, 1)
        _FloorAlbedoB ("Floor Albedo B", Color) = (1, 1, 1, 1)
        _SkyTopColor ("Sky Top Color", Color) = (1, 1, 1, 1)
        _SkyBottomColor ("Sky Bottom Color", Color) = (1, 1, 1, 1)
    }
    SubShader
    {
        Tags
        {
            "RenderType" = "Opaque"
        }

        Pass
        {
            Cull Off
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"
            #include "UnityLightingCommon.cginc"

            float3 _BallAlbedo;
            float3 _FloorAlbedoA;
            float3 _FloorAlbedoB;
            float3 _SkyTopColor;
            float3 _SkyBottomColor;

            struct appdata
            {
                float4 vertex: POSITION;
                float2 uv: TEXCOORD0;
            };

            struct v2f
            {
                float2 uv: TEXCOORD0;
                float4 vertex: SV_POSITION;
            };

            v2f vert(appdata v)
            {
                v2f o;

                o.vertex = float4(v.vertex.xy * 2.0, 0.5, 1.0);
                o.uv = v.uv;
                return o;
            }

            float mod(float x, float y)
            {
                return x - y * floor(x / y);
            }

            float sdSphere(float3 p, float r)
            {
                return length(p) - r;
            }

            float sdPlane(float3 p, float3 n, float h)
            {
                // nは正規化された法線
                // hは原点からの距離
                return dot(p, n) + h;
            }

            float dBall(float3 p)
            {
                return sdSphere(p - float3(0, 1, 0), 1);
            }

            float dFloor(float3 p)
            {
                return sdPlane(p, float3(0, 1, 0), 0);
            }

            float map(float3 p)
            {
                float d = dBall(p);
                d = min(d, dFloor(p));
                return d;
            }

            // 偏微分から法線を計算します
            float3 calcNormal(float3 p)
            {
                float eps = 0.001;

                return normalize(float3(
                    map(p + float3(eps, 0.0, 0.0)) - map(p + float3(-eps, 0.0, 0.0)),
                    map(p + float3(0.0, eps, 0.0)) - map(p + float3(0.0, -eps, 0.0)),
                    map(p + float3(0.0, 0.0, eps)) - map(p + float3(0.0, 0.0, -eps))
                ));
            }

            float calcAO(float3 pos, float3 nor)
            {
                float occ = 0.0;
                float sca = 1.0;
                for (int i = 0; i < 5; i++)
                {
                    float h = 0.01 + 0.12 * float(i) / 4.0;
                    float d = map(pos + h * nor).x;
                    occ += (h - d) * sca;
                    sca *= 0.95;
                    if (occ > 0.35) break;
                }
                return clamp(1.0 - 3.0 * occ, 0.0, 1.0) * (0.5 + 0.5 * nor.y);
            }

            // http://iquilezles.org/www/articles/rmshadows/rmshadows.htm
            float calcSoftshadow(float3 ro, float3 rd, float mint, float tmax)
            {
                // bounding volume
                float tp = (0.8 - ro.y) / rd.y;
                if (tp > 0.0) tmax = min(tmax, tp);

                float res = 1.0;
                float t = mint;
                for (int i = 0; i < 24; i++)
                {
                    float h = map(ro + rd * t).x;
                    float s = clamp(8.0 * h / t, 0.0, 1.0);
                    res = min(res, s * s * (3.0 - 2.0 * s));
                    t += clamp(h, 0.02, 0.2);
                    if (res < 0.004 || t > tmax) break;
                }
                return clamp(res, 0.0, 1.0);
            }

            float3 acesFilm(float3 x)
            {
                const float a = 2.51;
                const float b = 0.03;
                const float c = 2.43;
                const float d = 0.59;
                const float e = 0.14;
                return saturate((x * (a * x + b)) / (x * (c * x + d) + e));
            }

            float4x4 inverse(float4x4 m)
            {
                float n11 = m[0][0], n12 = m[1][0], n13 = m[2][0], n14 = m[3][0];
                float n21 = m[0][1], n22 = m[1][1], n23 = m[2][1], n24 = m[3][1];
                float n31 = m[0][2], n32 = m[1][2], n33 = m[2][2], n34 = m[3][2];
                float n41 = m[0][3], n42 = m[1][3], n43 = m[2][3], n44 = m[3][3];

                float t11 = n23 * n34 * n42 - n24 * n33 * n42 + n24 * n32 * n43 - n22 * n34 * n43 - n23 * n32 * n44 +
                    n22 * n33 * n44;
                float t12 = n14 * n33 * n42 - n13 * n34 * n42 - n14 * n32 * n43 + n12 * n34 * n43 + n13 * n32 * n44 -
                    n12 * n33 * n44;
                float t13 = n13 * n24 * n42 - n14 * n23 * n42 + n14 * n22 * n43 - n12 * n24 * n43 - n13 * n22 * n44 +
                    n12 * n23 * n44;
                float t14 = n14 * n23 * n32 - n13 * n24 * n32 - n14 * n22 * n33 + n12 * n24 * n33 + n13 * n22 * n34 -
                    n12 * n23 * n34;

                float det = n11 * t11 + n21 * t12 + n31 * t13 + n41 * t14;
                float idet = 1.0f / det;

                float4x4 ret;

                ret[0][0] = t11 * idet;
                ret[0][1] = (n24 * n33 * n41 - n23 * n34 * n41 - n24 * n31 * n43 + n21 * n34 * n43 + n23 * n31 * n44 -
                    n21 * n33 * n44) * idet;
                ret[0][2] = (n22 * n34 * n41 - n24 * n32 * n41 + n24 * n31 * n42 - n21 * n34 * n42 - n22 * n31 * n44 +
                    n21 * n32 * n44) * idet;
                ret[0][3] = (n23 * n32 * n41 - n22 * n33 * n41 - n23 * n31 * n42 + n21 * n33 * n42 + n22 * n31 * n43 -
                    n21 * n32 * n43) * idet;

                ret[1][0] = t12 * idet;
                ret[1][1] = (n13 * n34 * n41 - n14 * n33 * n41 + n14 * n31 * n43 - n11 * n34 * n43 - n13 * n31 * n44 +
                    n11 * n33 * n44) * idet;
                ret[1][2] = (n14 * n32 * n41 - n12 * n34 * n41 - n14 * n31 * n42 + n11 * n34 * n42 + n12 * n31 * n44 -
                    n11 * n32 * n44) * idet;
                ret[1][3] = (n12 * n33 * n41 - n13 * n32 * n41 + n13 * n31 * n42 - n11 * n33 * n42 - n12 * n31 * n43 +
                    n11 * n32 * n43) * idet;

                ret[2][0] = t13 * idet;
                ret[2][1] = (n14 * n23 * n41 - n13 * n24 * n41 - n14 * n21 * n43 + n11 * n24 * n43 + n13 * n21 * n44 -
                    n11 * n23 * n44) * idet;
                ret[2][2] = (n12 * n24 * n41 - n14 * n22 * n41 + n14 * n21 * n42 - n11 * n24 * n42 - n12 * n21 * n44 +
                    n11 * n22 * n44) * idet;
                ret[2][3] = (n13 * n22 * n41 - n12 * n23 * n41 - n13 * n21 * n42 + n11 * n23 * n42 + n12 * n21 * n43 -
                    n11 * n22 * n43) * idet;

                ret[3][0] = t14 * idet;
                ret[3][1] = (n13 * n24 * n31 - n14 * n23 * n31 + n14 * n21 * n33 - n11 * n24 * n33 - n13 * n21 * n34 +
                    n11 * n23 * n34) * idet;
                ret[3][2] = (n14 * n22 * n31 - n12 * n24 * n31 - n14 * n21 * n32 + n11 * n24 * n32 + n12 * n21 * n34 -
                    n11 * n22 * n34) * idet;
                ret[3][3] = (n12 * n23 * n31 - n13 * n22 * n31 + n13 * n21 * n32 - n11 * n23 * n32 - n12 * n21 * n33 +
                    n11 * n22 * n33) * idet;

                return ret;
            }


            float4 frag(v2f input): SV_Target
            {
                float3 col = float3(0.0, 0.0, 0.0);

                // UVを -1～1 の範囲に変換します
                float2 uv = 2.0 * input.uv - 1.0;

                float4 clipray = float4(uv, 0, 1);
                float4x4 invUnityMatrixP = inverse(UNITY_MATRIX_P);
                float3 viewRay = mul(invUnityMatrixP, clipray);
                float3 cameraOrigin = _WorldSpaceCameraPos;
                float3 ray = mul(transpose((float3x3)UNITY_MATRIX_V), viewRay); // ワールド空間のレイ

                // レイマーチング
                float t = 0.0; // レイの進んだ距離
                float3 p = cameraOrigin; // レイの先端の座標
                int i = 0; // レイマーチングのループカウンター
                bool hit = false; // オブジェクトに衝突したかどうか

                for (i = 0; i < 500; i++)
                {
                    float d = map(p); // 最短距離を計算します

                    // 最短距離を0に近似できるなら、オブジェクトに衝突したとみなして、ループを抜けます
                    if (d < 0.0001)
                    {
                        hit = true;
                        break;
                    }

                    t += d; // 最短距離だけレイを進めます
                    p = cameraOrigin + ray * t; // レイの先端の座標を更新します
                }

                if (hit)
                {
                    // ライティングのパラメーター
                    float3 normal = calcNormal(p); // 法線
                    float3 light = _WorldSpaceLightPos0; // 平行光源の方向ベクトル

                    // マテリアルのパラメーター
                    float3 albedo = float3(1, 1, 1); // アルベド
                    float metalness = 0.5; // メタルネス（金属の度合い）

                    // ボールのマテリアルを設定
                    if (dBall(p) < 0.0001)
                    {
                        albedo = _BallAlbedo;
                        metalness = 0.8;
                    }

                    // 床のマテリアルを設定
                    if (dFloor(p) < 0.0001)
                    {
                        float checker = mod(floor(p.x) + floor(p.z), 2.0);
                        albedo = lerp(_FloorAlbedoA, _FloorAlbedoB, checker);
                        metalness = 0.1;
                    }

                    // ライティング計算
                    float diffuse = saturate(dot(normal, light)); // 拡散反射
                    float specular = pow(saturate(dot(reflect(light, normal), ray)), 10.0); // 鏡面反射
                    float ao = calcAO(p, normal); // AO
                    float shadow = calcSoftshadow(p, light, 0.25, 5); // シャドウ

                    // ライティング結果の合成
                    col += albedo * diffuse * shadow * (1 - metalness) * _LightColor0.rgb; // 直接光の拡散反射
                    col += albedo * specular * shadow * metalness * _LightColor0.rgb; // 直接光の鏡面反射
                    col += albedo * ao * lerp(_SkyBottomColor, _SkyTopColor, 0.3); // 環境光

                    // 遠景のフォグ
                    float invFog = exp(-0.02 * t);
                    col = lerp(_SkyBottomColor, col, invFog);
                }
                else
                {
                    // 空
                    col = lerp(_SkyBottomColor, _SkyTopColor, ray.y);
                }

                // トーンマッピング
                col = acesFilm(col * 0.8);

                // ガンマ補正
                col = pow(col, 1 / 2.2);

                return float4(col, 1);
            }
            ENDCG

        }
    }
}