"""Shared, explicit test-export preset used by both desktop and CLI."""
import json
from pathlib import Path
from .common import ROOT, DATA, font_bank
from .compiler import compile_skin
from .mui import parse
from .output_contract import require_native_key_backend

RATIO=1024/600


def compile_preview(source,destination,keys,*,archive_input=False,runtime_phase_profile=False,native_musicbar_camera_local_candidate=False,native_ui_atlas_candidate=False,native_packed_mesh_candidate=False,native_canvas_text_candidate=False,native_numeric_float_candidate=False,native_combined_position_candidate=False,native_frame_mesh_candidate=False,native_dynamic_mesh_candidate=False,native_carrier_window_candidate=False,native_instruction_profile_candidate=False,native_ui_schedule_candidate=False,native_note_layout_candidate=False,native_math_module=None,native_transform_submit_candidate=False,native_vertex_upload_candidate=False,native_text_read_candidate=False,native_ui_submit_candidate=False,native_retained_text_candidate=False,native_stable_text_basis_candidate=False,native_plane_text_candidate=False,source_platform='windows',native_font_outline_candidate=False,font_build_context=None,progress=lambda message:None):
    require_native_key_backend()
    source,destination=Path(source),Path(destination).resolve()
    for parent in (destination,*destination.parents):
        if (parent/'malody.exe').is_file() or ((parent/'Malody V.exe').is_file() and (parent/'GameAssembly.dll').is_file()):
            raise ValueError('导出位置不能位于 Malody 安装目录内，请选择普通文件夹')
    doc=parse(source,keys,RATIO,platform=source_platform)
    candidate_projection=None
    if archive_input:
        # An archive has no installation/window ancestry. Preserve the preview
        # reference explicitly, without claiming this archive's context was proved.
        bank=json.loads((font_bank()/'font-bank.json').read_text(encoding='utf-8'))
        candidate_projection=dict(bank['native_ui_projection'])
        candidate_projection['source_context_verified']=False
        candidate_projection['method']='explicit-preview-reference'
    report=compile_skin(source,destination,keys,RATIO,draft=True,ui_rounding_height=600,
        native_font_bank=font_bank(),native_font_runtime_cache=True,
        native_clock_candidate=True,native_scroll_candidate=True,native_key_judge_candidate=True,
        native_layer_order_candidate=True,native_lifetime_candidate=True,native_prelude_candidate=True,
        native_bar_source_candidate='bar' in doc.elements,
        native_musicbar_clip_w_candidate='musicbar' in doc.elements,
        candidate_projection=candidate_projection,native_font_generator=archive_input,native_font_outline_candidate=native_font_outline_candidate,font_build_context=font_build_context,progress=progress,runtime_phase_profile=runtime_phase_profile,native_musicbar_camera_local_candidate=native_musicbar_camera_local_candidate,native_ui_atlas_candidate=native_ui_atlas_candidate,native_packed_mesh_candidate=native_packed_mesh_candidate,native_canvas_text_candidate=native_canvas_text_candidate,native_numeric_float_candidate=native_numeric_float_candidate,native_combined_position_candidate=native_combined_position_candidate,native_frame_mesh_candidate=native_frame_mesh_candidate,native_dynamic_mesh_candidate=native_dynamic_mesh_candidate,native_carrier_window_candidate=native_carrier_window_candidate,native_instruction_profile_candidate=native_instruction_profile_candidate,native_ui_schedule_candidate=native_ui_schedule_candidate,native_note_layout_candidate=native_note_layout_candidate,native_math_module=native_math_module,native_transform_submit_candidate=native_transform_submit_candidate,native_vertex_upload_candidate=native_vertex_upload_candidate,native_text_read_candidate=native_text_read_candidate,native_ui_submit_candidate=native_ui_submit_candidate,native_retained_text_candidate=native_retained_text_candidate,native_stable_text_basis_candidate=native_stable_text_basis_candidate,native_plane_text_candidate=native_plane_text_candidate,source_platform=source_platform)
    report['test_export']={'preset':'native-key-preview-dev8','one_to_one_verified':False,
        'maximum_chart_notes':16384,'reference_aspect':'1024:600','old_speed_scale':[1,1],
        'old_judge_ahead':160,'formal_acceptance':False}
    (destination/'conversion-report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    (destination/'测试说明.txt').write_text(
        '这是可导入的测试皮肤，尚未完成整套 1:1 验收。\n'
        '使用旁边的 .draft.msp 在 maV 中手动导入；转换器不会写入游戏安装目录。\n'
        '当前用于 MC / mania OSU 谱面测试（排序验证至 16384 音符）；验证基准为 1024:600，旧速度/缩放为 1。\n'
        '超范围、源谱面/原生音符数量不匹配或未支持的定义可能拒绝加载；详见 conversion-report.json。\n'
        '请重点对照渐入、长条落点、收缩退场、遮挡顺序与文字。\n',encoding='utf-8')
    return report
