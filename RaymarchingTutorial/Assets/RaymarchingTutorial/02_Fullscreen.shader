Shader "Unlit/02_Fullscreen"
{
    Properties { }
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
            
            float4 frag(v2f i): SV_Target
            {
                // UVグラディエントの色を計算します
                float4 col = float4(i.uv, 0.0, 1.0);
                return col;
            }
            ENDCG
            
        }
    }
}
