Shader "Unlit/RightUpFoward"
{
    Properties
    {
        _BallAlbedo ("Ball Albedo", Color) = (1, 0, 0, 1)
        _FloorAlbedoA ("Floor Albedo A", Color) = (0, 0, 0, 1)
        _FloorAlbedoB ("Floor Albedo B", Color) = (1, 1, 1, 1)
        _SkyTopColor ("Sky Top Color", Color) = (1, 1, 1, 1)
        _SkyBottomColor ("Sky Bottom Color", Color) = (1, 1, 1, 1)

        [Header(Quad)]
        _QuadPos ("Quad Pos", Vector) = (0, 1, -6, 1)
        _QuadSize ("Quad Size", Vector) = (1.6, 1, 0.001, 1)
        _QuadPixelCount ("Quad Pixel Count", Range(1, 40)) = 14

        [Header(Ray)]
        _RayScanProgress ("Ray Scan Progress", Range(0, 1)) = 0.65
        _RayCount ("Ray Count", Range(1, 20)) = 4
        _RayColorA ("Ray Color A", Color) = (1, 1, 0.2, 1)
        _RayColorB ("Ray Color B", Color) = (0.1, 0.1, 1, 0.8)

        [Header(Axis)]
        _AxisLength ("Axis Length", Range(0, 1)) = 0.5
        _AxisWidth ("Axis Width", Range(0, 0.1)) = 0.01
        _AxisArrowC ("Axis Arrow C", Range(-3, 3)) = 0.1
        _AxisArrowScale ("Axis Arrow Scale", Range(0, 6)) = 4

        [Header(Camera)]
        _CameraAlbedo ("Camera Albedo", Color) = (1, 0, 0, 1)
        _CameraPos ("Camera Pos", Vector) = (0, 1, -7, 1)
        _CameraSize ("Camera Size", Vector) = (0.1, 0.1, 0.1, 1)
    }
    SubShader
    {
        Tags { "RenderType" = "Opaque" }
        
        Pass
        {
            Cull Off
            CGPROGRAM
            
            #pragma vertex vert
            #pragma fragment frag
            
            #include "UnityCG.cginc"
            #include "UnityLightingCommon.cginc"

            #define PI 3.14159265359
            #define TAU 6.28318530718
            
            float3 _BallAlbedo;
            float3 _FloorAlbedoA;
            float3 _FloorAlbedoB;
            float3 _SkyTopColor;
            float3 _SkyBottomColor;

            float3 _QuadPos;
            float3 _QuadSize;
            float _QuadPixelCount;

            float _RayScanProgress;
            float _RayCount;
            float4 _RayColorA;
            float4 _RayColorB;

            float _AxisLength;
            float _AxisWidth;
            float _AxisArrowC;
            float _AxisArrowScale;
            
            float4 _CameraAlbedo;
            float3 _CameraPos;
            float3 _CameraSize;

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
                
                o.vertex = float4(v.vertex.xy, 0.5, 1.0);
                
                o.uv = v.uv;
                
                // Direct3DのようにUVの上下が反転したプラットフォームを考慮します
                #if UNITY_UV_STARTS_AT_TOP
                    o.uv.y = 1 - o.uv.y;
                #endif
                
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

            float sdBox(float3 p, float3 b)
            {
                float3 q = abs(p) - b;
                return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
            }
            
            float sdPlane(float3 p, float3 n, float h)
            {
                // nは正規化された法線
                // hは原点からの距離
                return dot(p, n) + h;
            }

            float sdCappedCylinder(float3 p, float h, float r)
            {
                float2 d = abs(float2(length(p.xz), p.y)) - float2(h, r);
                return min(max(d.x, d.y), 0.0) + length(max(d, 0.0));
            }

            float sdLine(float3 p, float3 a, float3 b, float r)
            {
                float3 pa = p - a, ba = b - a;
                float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
                return length(pa - ba * h) - r;
            }

            float sdCone(in float3 p, in float2 c, float h)
            {
                // c is the sin/cos of the angle, h is height
                // Alternatively pass q instead of (c,h),
                // which is the point at the base in 2D
                float2 q = h * float2(c.x / c.y, -1.0);
                
                float2 w = float2(length(p.xz), p.y);
                float2 a = w - q * clamp(dot(w, q) / dot(q, q), 0.0, 1.0);
                float2 b = w - q * float2(clamp(w.x / q.x, 0.0, 1.0), 1.0);
                float k = sign(q.y);
                float d = min(dot(a, a), dot(b, b));
                float s = max(k * (w.x * q.y - w.y * q.x), k * (w.y - q.y));
                return sqrt(d) * sign(s);
            }

            
            float sdCone_(float3 p, float2 c, float h)
            {
                float q = length(p.xz);
                return max(dot(c.xy, float2(q, p.y)), -h - p.y);
            }

            float2x2 rotate(in float a)
            {
                float s = sin(a), c = cos(a);
                return float2x2(c, s, -s, c);
            }
            
            float dBall(float3 p)
            {
                return sdSphere(p - float3(0, 1, 0), 1);
            }
            
            float dFloor(float3 p)
            {
                return sdPlane(p, float3(0, 1, 0), 0);
            }

            float dQuad(float3 p)
            {
                return sdBox(p - _QuadPos, _QuadSize);
            }

            float dCamera(float3 p)
            {
                float3 q = p - _CameraPos;
                float d = sdBox(q, _CameraSize);

                q.yz = mul(rotate(3.141592 * 0.5), q.yz);
                d = min(d, sdCappedCylinder(q + float3(0, -0.05, 0), 0.05, 0.05));

                return d;
            }
            
            float map(float3 p)
            {
                float d = dBall(p);
                d = min(d, dFloor(p));
                d = min(d, dCamera(p));
                return d;
            }

            float mapShadow(float3 p)
            {
                float d = map(p);
                d = min(d, dQuad(p));
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
                    float d = mapShadow(pos + h * nor).x;
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
                    float h = mapShadow(ro + rd * t).x;
                    float s = clamp(8.0 * h / t, 0.0, 1.0);
                    res = min(res, s * s * (3.0 - 2.0 * s));
                    t += clamp(h, 0.02, 0.2);
                    if (res < 0.004 || t > tmax) break;
                }
                return clamp(res, 0.0, 1.0);
            }

            float dAxisRight(float3 p)
            {
                float3 from = _CameraPos + float3(0, 0, 0.12);
                float d = sdLine(p, from, from + float3(_AxisLength, 0, 0), _AxisWidth);

                float3 q = p - from;
                q.xy = mul(rotate(-PI * 0.5), q.xy);
                q.y -= (_AxisLength + 0.1);
                q.xz *= _AxisArrowScale;
                
                d = min(d, sdCone(q, 1, 0.1) / _AxisArrowScale);
                return d;
            }

            float dAxisUp(float3 p)
            {
                float3 from = _CameraPos + float3(0, 0, 0.12);
                float d = sdLine(p, from, from + float3(0, _AxisLength, 0), _AxisWidth);

                float3 q = p - from;
                // q.xy = mul(rotate(-PI * 0.5), q.xy);
                q.y -= (_AxisLength + 0.1);
                q.xz *= _AxisArrowScale;
                
                d = min(d, sdCone(q, 1, 0.1) / _AxisArrowScale);
                return d;
            }

            float dAxisForward(float3 p)
            {
                float3 from = _CameraPos + float3(0, 0, 0.12);
                float d = sdLine(p, from, from + float3(0, 0, _AxisLength), _AxisWidth);

                float3 q = p - from;
                q.zy = mul(rotate(-PI * 0.5), q.zy);
                q.y -= (_AxisLength + 0.1);
                q.xz *= _AxisArrowScale;
                
                d = min(d, sdCone(q, 1, 0.1) / _AxisArrowScale);
                return d;
            }

            float dGizmo(float3 p)
            {
                float d = dAxisRight(p);
                d = min(d, dAxisUp(p));
                d = min(d, dAxisForward(p));
                
                return d;
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

            // フレネル項のSchlick近似
            float fresnelSchlick(float f0, float cosTheta)
            {
                return f0 + (1.0 - f0) * pow((1.0 - cosTheta), 5.0);
            }

            // https://github.com/hecomi/UnityRaymarchingForward/blob/master/Assets/RaymarchingForward/Shaders/Raymarching.cginc#L63-L77
            inline float EncodeDepth(float4 pos)
            {
                float z = pos.z / pos.w;
                #if defined(SHADER_API_GLCORE) || defined(SHADER_API_OPENGL) || defined(SHADER_API_GLES) || defined(SHADER_API_GLES3)
                    return z * 0.5 + 0.5;
                #else
                    return z;
                #endif
            }

            inline float GetCameraDepth(float3 pos)
            {
                float4 vpPos = mul(UNITY_MATRIX_VP, float4(pos, 1.0));
                return EncodeDepth(vpPos);
            }

            // checkerbord
            // https://www.shadertoy.com/view/XlcSz2
            float checkersTextureGradBox(in float2 p, in float2 ddx, in float2 ddy)
            {
                // filter kernel
                float2 w = max(abs(ddx), abs(ddy)) + 0.01;
                // analytical integral (box filter)
                float2 i = 2.0 * (abs(frac((p - 0.5 * w) / 2.0) - 0.5) - abs(frac((p + 0.5 * w) / 2.0) - 0.5)) / w;
                // xor pattern
                return 0.5 - 0.5 * i.x * i.y;
            }

            float3 raymarching(inout float3 origin, inout float3 ray, inout bool hit, inout float3 reflectionAttenuation, inout float t)
            {
                float3 col = float3(0.0, 0.0, 0.0);

                // レイマーチング
                hit = false;
                t = 0.0;// レイの進んだ距離
                float3 p = origin;// レイの先端の座標
                int i = 0;// レイマーチングのループカウンター
                
                for (i = 0; i < 500; i++)
                {
                    float d = map(p);// 最短距離を計算します
                    
                    // 最短距離を0に近似できるなら、オブジェクトに衝突したとみなして、ループを抜けます
                    if (d < 0.0001)
                    {
                        hit = true;
                        break;
                    }
                    
                    t += d;// 最短距離だけレイを進めます
                    p = origin + ray * t;// レイの先端の座標を更新します
                }
                
                if (hit)
                {
                    // ライティングのパラメーター
                    float3 normal = calcNormal(p);// 法線
                    float3 light = _WorldSpaceLightPos0;// 平行光源の方向ベクトル
                    float3 ref = reflect(ray, normal);// レイの反射ベクトル
                    float f0 = 1;// フレネル反射率F0
                    
                    // マテリアルのパラメーター
                    float3 albedo = float3(1, 1, 1);// アルベド
                    float metalness = 0.5;// メタルネス（金属の度合い）
                    
                    // ボールのマテリアルを設定
                    if (dBall(p) < 0.0001)
                    {
                        albedo = _BallAlbedo;
                        metalness = 0.8;
                        f0 = 0.3;
                    }
                    
                    // 床のマテリアルを設定
                    else if (dFloor(p) < 0.0001)
                    {
                        float2 ddx_uvw = ddx(p.xz);
                        float2 ddy_uvw = ddy(p.xz);
                        float checker = checkersTextureGradBox(p.xz, ddy_uvw, ddy_uvw);
                        albedo = lerp(_FloorAlbedoA, _FloorAlbedoB, checker);
                        metalness = 0.1;
                        f0 = 0.4;
                    }

                    // カメラのマテリアルを設定
                    else if (dCamera(p) < 0.0001)
                    {
                        albedo = _CameraAlbedo.rgb;
                        metalness = _CameraAlbedo.a;
                        f0 = 0.1;
                    }
                    
                    
                    // ライティング計算
                    float diffuse = saturate(dot(normal, light));// 拡散反射
                    float specular = pow(saturate(dot(reflect(light, normal), ray)), 10.0);// 鏡面反射
                    float ao = calcAO(p, normal);// AO
                    float shadow = calcSoftshadow(p, light, 0.25, 5);// シャドウ
                    
                    // ライティング結果の合成
                    col += albedo * diffuse * shadow * (1 - metalness) * _LightColor0.rgb;// 直接光の拡散反射
                    col += albedo * specular * shadow * metalness * _LightColor0.rgb;// 直接光の鏡面反射
                    col += albedo * ao * lerp(_SkyBottomColor, _SkyTopColor, 0.3);// 環境光
                    
                    // 遠景のフォグ
                    float invFog = exp(-0.02 * t);
                    col = lerp(_SkyBottomColor, col, invFog);
                    
                    // 反射の減衰率を更新。シェーダーでは再帰が使えないため、呼び出し側で結果を合成
                    reflectionAttenuation *= albedo * fresnelSchlick(f0, dot(ref, normal)) * invFog;

                    // レイを反射用に更新
                    origin = p + 0.01 * normal;
                    ray = ref;
                }
                else
                {
                    // 空
                    col = lerp(_SkyBottomColor, _SkyTopColor, ray.y);
                    origin = p;
                }

                return col;
            }

            void intersectToQuad(inout float3 origin, inout float3 ray, inout bool hit, inout float2 quadUv, inout float t)
            {
                // レイマーチング
                hit = false;
                t = 0.0;// レイの進んだ距離
                float3 p = origin;// レイの先端の座標
                int i = 0;// レイマーチングのループカウンター
                
                for (i = 0; i < 500; i++)
                {
                    float d = dQuad(p);// 最短距離を計算します
                    
                    // 最短距離を0に近似できるなら、オブジェクトに衝突したとみなして、ループを抜けます
                    if (d < 0.0001)
                    {
                        hit = true;
                        quadUv = (p - _QuadPos) / _QuadSize;
                        return;
                    }
                    
                    t += d;// 最短距離だけレイを進めます
                    p = origin + ray * t;// レイの先端の座標を更新します
                }
            }

            void intersectToGizmo(inout float3 origin, inout float3 ray, inout bool hit, inout float t, inout float3 p)
            {
                // レイマーチング
                hit = false;
                t = 0.0;// レイの進んだ距離
                p = origin;// レイの先端の座標
                
                for (int i = 0; i < 300; i++)
                {
                    float d = dGizmo(p);// 最短距離を計算します
                    
                    // 最短距離を0に近似できるなら、オブジェクトに衝突したとみなして、ループを抜けます
                    if (d < 0.0001)
                    {
                        hit = true;
                        return;
                    }
                    
                    t += d;// 最短距離だけレイを進めます
                    p = origin + ray * t;// レイの先端の座標を更新します
                }
            }

            float dGrid(float x)
            {
                x = frac(x);
                return min(x, 1 - x);
            }

            float dGrid(float2 p)
            {
                return min(dGrid(p.x), dGrid(p.y));
            }
            
            void frag(v2f input, out float4 color: SV_Target, out float depth: SV_Depth)
            {
                float3 col = float3(0.0, 0.0, 0.0);
                
                // UVを -1～1 の範囲に変換します
                float2 uv = 2.0 * input.uv - 1.0;
                
                // カメラの位置
                float3 cameraOrigin = _WorldSpaceCameraPos;
                
                // カメラ行列からレイを生成します
                float4 clipRay = float4(uv, 1, 1);// クリップ空間のレイ
                float3 viewRay = normalize(mul(unity_CameraInvProjection, clipRay).xyz);// ビュー空間のレイ
                float3 ray = mul(transpose((float3x3)UNITY_MATRIX_V), viewRay);// ワールド空間のレイ

                bool hit = false;// オブジェクトに衝突したかどうか
                float3 reflectionAttenuation = float3(1, 1, 1);// 反射の減衰率
                float sceneDepth = 0;

                // バックアップ
                float3 ray0 = ray;
                float3 cameraOrigin0 = cameraOrigin;

                // レイは最大3回まで反射します
                for (int i = 0; i < 3; i++)
                {
                    float t;
                    col += reflectionAttenuation * raymarching(cameraOrigin, ray, hit, reflectionAttenuation, t);

                    if (i == 0)
                    {
                        depth = GetCameraDepth(cameraOrigin);
                        sceneDepth = t;
                    }

                    if (!hit) break;
                }


                // レイマーチング用の仮想スクリーン
                float2 quadUv = float2(0, 0);
                cameraOrigin = cameraOrigin0;
                ray = ray0;
                float quadDepth = 0;
                intersectToQuad(cameraOrigin, ray, hit, quadUv, quadDepth);

                if (hit && quadDepth < sceneDepth)
                {
                    float3 quadColor = float3(0.0, 0.0, 0.0);

                    // カメラの情報
                    float3 cameraOrigin = _CameraPos + float3(0, 0, 0.12);// カメラの位置
                    float3 cameraTarget = float3(0, 1, 0);// カメラのターゲット
                    float3 cameraUp = float3(0, 1, 0);// カメラのUPベクトル
                    
                    // UVに対応するレイを計算
                    float3 forward = normalize(cameraTarget - cameraOrigin);
                    float3 right = normalize(cross(forward, cameraUp));
                    float3 up = normalize(cross(right, forward));
                    
                    float3 ray = normalize(
                        right * quadUv.x * _QuadSize.x / _QuadSize.y +
                        up * quadUv.y +
                        forward * (_QuadPos.z - cameraOrigin.z) / _QuadSize.y
                    );

                    bool hit = false;// オブジェクトに衝突したかどうか
                    float3 reflectionAttenuation = float3(1, 1, 1);// 反射の減衰率

                    // レイは最大3回まで反射します
                    for (int i = 0; i < 3; i++)
                    {
                        float t;
                        quadColor += reflectionAttenuation * raymarching(cameraOrigin, ray, hit, reflectionAttenuation, t);

                        if (!hit) break;
                    }

                    // grid
                    float2 gridCount = floor(float2(_QuadPixelCount * _QuadSize.x / _QuadSize.y, _QuadPixelCount));
                    float2 gridUv = (0.5 + float2(0.5, -0.5) * quadUv) * gridCount;
                    float2 grid = floor(gridUv);
                    float progress = grid.y * gridCount.x + grid;

                    if (progress > _RayScanProgress * gridCount.x * gridCount.y)
                    {
                        // col = lerp(col, float3(0.5, 0.5, 0), 0.1);
                        col = float3(0.5 + 0.5 * quadUv, 0.0);
                    }
                    else
                    {
                        col = lerp(col, quadColor, 1);
                    }

                    // grid line
                    col = lerp(col, float3(0, 0.2, 0), saturate(1 - smoothstep(0, 0.15, dGrid(gridUv))));
                }

                // Gizmo(Ray)
                float gizmoDepth = 0;
                float3 gizmoHit;
                cameraOrigin = cameraOrigin0;
                ray = ray0;

                intersectToGizmo(cameraOrigin, ray, hit, gizmoDepth, gizmoHit);

                if (hit)
                {
                    float a = 0.9;
                    float2 c = float2(1.0, 0.1);

                    if (dAxisRight(gizmoHit) < 0.001)
                    {
                        col = lerp(col, c.xyy, a);
                    }
                    else if (dAxisUp(gizmoHit) < 0.001)
                    {
                        col = lerp(col, c.yxy, a);
                    }
                    else if (dAxisForward(gizmoHit) < 0.001)
                    {
                        col = lerp(col, c.yyx, a);
                    }
                }
                
                // トーンマッピング
                col = acesFilm(col * 0.8);
                
                // ガンマ補正
                col = pow(col, 1 / 2.2);
                
                color = float4(col, 1);
            }
            ENDCG
            
        }
    }
}
