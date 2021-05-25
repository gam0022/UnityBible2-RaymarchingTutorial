using UnityEditor;
using UnityEngine;
using System.IO;

public static class RaymarchingQuadMeshCreator
{
    static readonly string outputPath =
            "Assets/RaymarchingTutorial/Resources/RaymarchingQuad.mesh";
    const int expandBounds = 10000;// 拡張するサイズ

    [MenuItem("Tools/CreateRaymarchingQuadMesh")]
    static void CreateRaymarchingQuadMesh()
    {
        // MeshのAssetを作成します
        var mesh = new Mesh
        {
            vertices = new[]
            {
                new Vector3(1f, 1f, 0f),
                new Vector3(-1f, 1f, 0f),
                new Vector3(-1f, -1f, 0f),
                new Vector3(1f, -1f, 0f),
            },
            uv = new[]
            {
                new Vector2(1f, 1f),
                new Vector2(0f, 1f),
                new Vector2(0f, 0f),
                new Vector2(1f, 0f),
            },
            triangles = new[] { 0, 1, 2, 2, 3, 0 }
        };
        mesh.RecalculateNormals();
        mesh.RecalculateBounds();

        // バウンディングボックスを拡張します
        var bounds = mesh.bounds;
        bounds.Expand(expandBounds);
        mesh.bounds = bounds;

        SafeCreateDirectory(Path.GetDirectoryName(outputPath));

        var oldAsset = AssetDatabase.LoadAssetAtPath<Mesh>(outputPath);
        if (oldAsset)
        {
            // 既にAssetがある場合は更新します
            oldAsset.Clear();// Meshアセット更新の直前に Clear() が必要です
            EditorUtility.CopySerialized(mesh, oldAsset);
            AssetDatabase.SaveAssets();
        }
        else
        {
            // まだAssetがない場合は新規作成します
            AssetDatabase.CreateAsset(mesh, outputPath);
            AssetDatabase.Refresh();
        }
    }

    // ディレクトリが存在しない場合に作ります
    static DirectoryInfo SafeCreateDirectory(string path)
    {
        if (Directory.Exists(path))
        {
            return null;
        }

        return Directory.CreateDirectory(path);
    }
}
