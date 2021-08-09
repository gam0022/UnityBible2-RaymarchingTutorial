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
        Tags { "RenderType" = "Opaque" }
        
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
            
            float4 frag(v2f input): SV_Target
            {
                float3 col = float3(0.0, 0.0, 0.0);
                
                // UVを -1～1 の範囲に変換します
                float2 uv = 2.0 * input.uv - 1.0;

                float fov = 60;
                float degree2rad = UNITY_PI/180.0f;
                float tangent = tan(fov*degree2rad*0.5);
                float3 viewRay = float3(uv*tangent, -1);
                viewRay = normalize(viewRay);
                
                // カメラの位置
                float3 cameraOrigin = _WorldSpaceCameraPos;
                
                // カメラ行列からレイを生成します
                //float4 clipRay = float4(uv, 1, 1);// クリップ空間のレイ
                //float3 viewRay = normalize(mul(unity_CameraInvProjection, clipRay).xyz);// ビュー空間のレイ
                float3 ray = mul(transpose((float3x3)UNITY_MATRIX_V), viewRay);// ワールド空間のレイ
                
                // レイマーチング
                float t = 0.0;// レイの進んだ距離
                float3 p = cameraOrigin;// レイの先端の座標
                int i = 0;// レイマーチングのループカウンター
                bool hit = false;// オブジェクトに衝突したかどうか
                
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
                    p = cameraOrigin + ray * t;// レイの先端の座標を更新します
                }
                
                if (hit)
                {
                    // ライティングのパラメーター
                    float3 normal = calcNormal(p);// 法線
                    float3 light = _WorldSpaceLightPos0;// 平行光源の方向ベクトル
                    
                    // マテリアルのパラメーター
                    float3 albedo = float3(1, 1, 1);// アルベド
                    float metalness = 0.5;// メタルネス（金属の度合い）
                    
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
