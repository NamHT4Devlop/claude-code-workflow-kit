// @ts-nocheck
// Vietnamese UI strings for the panel.
//
// The repo's source is English; this file is the one deliberate exception, because these strings
// ARE the product for a Vietnamese-speaking PM/SM. Keys are the English strings themselves, so an
// untranslated string simply falls through to English instead of showing a missing-key placeholder.
//
// Only the panel chrome is translated. What Claude writes back is in whatever language the skill
// produced — the skills already write dual-audience Vietnamese sections where it matters.
const I18N_VI = {
  // ---- categories ----
  'General': 'Chung',
  'Understand': 'Hiểu hệ thống',
  'Plan': 'Lập kế hoạch',
  'Build & Fix': 'Code & sửa lỗi',
  'Ops & Docs': 'Vận hành & tài liệu',

  // ---- card titles ----
  'Ask anything': 'Hỏi bất cứ điều gì',
  'Scan → Knowledge Base': 'Quét → Knowledge Base',
  'Rescan (update KB)': 'Quét lại (cập nhật KB)',
  'Ask the codebase': 'Hỏi về codebase',
  'Dependency map': 'Sơ đồ phụ thuộc',
  'System map': 'Sơ đồ hệ thống',
  'Document a feature': 'Viết tài liệu tính năng',
  'Sharpen an idea': 'Làm rõ ý tưởng',
  'Plan an epic': 'Lập kế hoạch epic',
  'Review a plan': 'Review kế hoạch',
  'Create user stories': 'Tạo user story',
  'Stories → tracker issues': 'Story → issue trên tracker',
  'Build a feature': 'Làm một tính năng',
  'Fix a bug': 'Sửa bug',
  'Migration / deprecation': 'Migration / gỡ bỏ',
  'Simplify code': 'Đơn giản hoá code',
  'Optimize performance': 'Tối ưu hiệu năng',
  'Add observability': 'Thêm khả năng giám sát',
  'Port to another stack': 'Chuyển sang stack khác',
  'QA test cases': 'Test case cho QA',
  'Run E2E QA': 'Chạy QA E2E',
  'Security audit': 'Kiểm tra bảo mật',
  'Design / a11y review': 'Review giao diện / khả năng tiếp cận',
  'Prepare / review PR': 'Chuẩn bị / review PR',
  'Docs vs reality check': 'Đối chiếu tài liệu với code',
  'Splunk error digest': 'Tổng hợp lỗi từ Splunk',
  'Operational runbook': 'Runbook vận hành',
  'Export to PDF': 'Xuất ra PDF',
  'Create a new skill': 'Tạo skill mới',

  // ---- card descriptions ----
  'A general question — not tied to this repo. Runs plain Claude (no skill).':
    'Câu hỏi chung, không liên quan repo này. Chạy Claude thuần (không dùng skill).',
  'Generate the project Knowledge Base (run once).':
    'Tạo Knowledge Base cho dự án (chạy một lần).',
  'Refresh the KB after code changes.':
    'Làm mới KB sau khi code thay đổi.',
  'Plain-language answer + diagram + detail.':
    'Trả lời dễ hiểu + sơ đồ + chi tiết kỹ thuật.',
  'Interactive HTML code graph (opens in browser).':
    'Đồ thị code dạng HTML tương tác (mở trong trình duyệt).',
  'Cross-service map — open the workspace root.':
    'Sơ đồ liên service — mở ở thư mục gốc workspace.',
  'Business↔code doc anyone can follow.':
    'Tài liệu nghiệp vụ ↔ code ai đọc cũng hiểu.',
  'Turn a fuzzy idea into a crisp brief.':
    'Biến ý tưởng mơ hồ thành bản mô tả rõ ràng.',
  'Epic → features → user stories → sprint plan.':
    'Epic → tính năng → user story → kế hoạch sprint.',
  'Multi-lens critique + verdict.':
    'Phản biện nhiều góc nhìn + kết luận.',
  'Deep-investigate → features + INVEST stories, each AC as granular as possible.':
    'Điều tra kỹ → tính năng + story chuẩn INVEST, mỗi AC chi tiết nhất có thể.',
  'Turn a plan / user stories into GitHub or Jira issues. Previews first — nothing is created without your OK.':
    'Biến kế hoạch / user story thành issue trên GitHub hoặc Jira. Xem trước đã — không tạo gì nếu bạn chưa đồng ý.',
  '13-step pipeline: plan → code → review → test.':
    'Quy trình 13 bước: kế hoạch → code → review → test.',
  'Triage (code vs config/spec) → root-cause → regression test → minimal fix.':
    'Phân loại (do code hay config/spec) → tìm nguyên nhân gốc → test hồi quy → sửa tối thiểu.',
  'Safe API/DB/event/lib change with rollback.':
    'Thay đổi API/DB/event/thư viện an toàn, có đường lùi.',
  'Behavior-preserving cleanup; tests stay green.':
    'Dọn code mà không đổi hành vi; test vẫn xanh.',
  'Measure-first; prove before/after.':
    'Đo trước đã; chứng minh bằng số liệu trước/sau.',
  'Structured logs + trace IDs + metrics.':
    'Log có cấu trúc + trace ID + metrics.',
  'Rails+GraphQL → Spring Boot, contract + behavior preserved (golden-test verified).':
    'Rails+GraphQL → Spring Boot, giữ nguyên contract + hành vi (đối chiếu bằng golden test).',
  'Two-phase review vs the KB.':
    'Review hai giai đoạn, đối chiếu với KB.',
  'User story → new + regression cases.':
    'User story → case mới + case hồi quy.',
  'Drive a running app in a browser (needs a URL).':
    'Điều khiển app đang chạy qua trình duyệt (cần URL).',
  'Whole-repo OWASP + STRIDE sweep.':
    'Quét toàn repo theo OWASP + STRIDE.',
  'UI/UX + accessibility (URL or components).':
    'UI/UX + khả năng tiếp cận (URL hoặc component).',
  'Draft a PR desc, or review a PR#.':
    'Soạn mô tả PR, hoặc review một PR#.',
  'Find where the Knowledge Base, plans and code have drifted apart — read-only.':
    'Tìm chỗ Knowledge Base, kế hoạch và code đã lệch nhau — chỉ đọc.',
  'Per-app errors → table → Slack.':
    'Lỗi theo từng app → bảng → gửi Slack.',
  'What shipped + action items from git history.':
    'Đã ship gì + việc cần làm, lấy từ lịch sử git.',
  'Health checks, deploy/rollback and incident playbooks a teammate can follow at 2am.':
    'Kiểm tra sức khoẻ hệ thống, deploy/rollback và kịch bản xử lý sự cố — đọc lúc 2 giờ sáng vẫn làm theo được.',
  'Turn a report/doc into a PDF.':
    'Chuyển báo cáo/tài liệu thành PDF.',
  'Scaffold a new cwk-* skill (for devs).':
    'Tạo khung một skill cwk-* mới (cho dev).',

  // ---- field labels ----
  'Your question (any topic)': 'Câu hỏi của bạn (chủ đề bất kỳ)',
  'Your question': 'Câu hỏi của bạn',
  'Scope (optional)': 'Phạm vi (không bắt buộc)',
  'Feature / module / entity': 'Tính năng / module / thực thể',
  'The idea / problem': 'Ý tưởng / vấn đề',
  'Epic title': 'Tên epic',
  'Description (what & why)': 'Mô tả (làm gì & vì sao)',
  'The plan / user stories': 'Kế hoạch / user story',
  'Requirement / idea (leave blank if using Slack)': 'Yêu cầu / ý tưởng (bỏ trống nếu dùng Slack)',
  'Slack thread / channel URL (optional)': 'Link thread / kênh Slack (không bắt buộc)',
  'Plan or user-story file (blank = pick the most recent)': 'File kế hoạch / user story (bỏ trống = lấy file mới nhất)',
  'Target project': 'Dự án đích',
  'Create them for real (otherwise it only writes a preview file)': 'Tạo thật (nếu không thì chỉ ghi file xem trước)',
  'Requirement': 'Yêu cầu',
  'Error / stack trace, or a QA report (expected vs actual + repro + environment + failing case)':
    'Lỗi / stack trace, hoặc báo cáo QA (mong đợi vs thực tế + cách tái hiện + môi trường + case lỗi)',
  "What's changing": 'Thay đổi cái gì',
  'File / function (optional)': 'File / hàm (không bắt buộc)',
  'Slow area / endpoint / query': 'Chỗ chậm / endpoint / câu query',
  'Service / flow to instrument': 'Service / luồng cần gắn giám sát',
  'What to port (source → target stack, endpoint set)': 'Chuyển cái gì (stack nguồn → đích, danh sách endpoint)',
  'File / PR# (blank = current branch)': 'File / PR# (bỏ trống = nhánh hiện tại)',
  'User story + acceptance criteria': 'User story + tiêu chí chấp nhận',
  'App URL': 'URL của app',
  'URL or path': 'URL hoặc đường dẫn',
  'PR# to review (blank = prepare from branch)': 'PR# cần review (bỏ trống = soạn từ nhánh)',
  'Also refresh the stale docs it finds (--fix-docs)': 'Cập nhật luôn tài liệu đã lỗi thời (--fix-docs)',
  'index / env / app / window / Slack URL (blank = it asks)': 'index / môi trường / app / khoảng thời gian / URL Slack (bỏ trống = sẽ hỏi)',
  'Time window': 'Khoảng thời gian',
  'Service / scope (blank = it asks)': 'Service / phạm vi (bỏ trống = sẽ hỏi)',
  'File to export (.md/.html)': 'File cần xuất (.md/.html)',
  'Name + purpose': 'Tên + mục đích',
  'Model  ·  cheaper = fewer tokens / lower cost': 'Model  ·  rẻ hơn = ít token / chi phí thấp hơn',

  // ---- field hints ----
  'Asks you first, backs the files up, and only updates the Knowledge Base — never your source code.':
    'Sẽ hỏi bạn trước, sao lưu file, và chỉ cập nhật Knowledge Base — không bao giờ đụng vào source code.',
  'It still shows you every issue and asks before creating anything.':
    'Vẫn hiện cho bạn xem từng issue và hỏi trước khi tạo bất cứ thứ gì.',

  // ---- buttons, sections, status ----
  '▶  Run': '▶  Chạy',
  '⚡ Interactive': '⚡ Tương tác',
  'Fill the required field': 'Vui lòng điền ô bắt buộc',
  'Recent & running': 'Gần đây & đang chạy',
  'clear history': 'xoá lịch sử',
  'Home': 'Trang chủ',
  'Cancel': 'Huỷ',
  '📄 Report': '📄 Báo cáo',
  'Checking Claude Code…': 'Đang kiểm tra Claude Code…',
  'Claude Code ready': 'Claude Code đã sẵn sàng',
  'Claude Code CLI not found': 'Không tìm thấy Claude Code CLI',
  'Install it and sign in, or set cwkUi.claudePath.':
    'Hãy cài đặt và đăng nhập, hoặc chỉnh cwkUi.claudePath.',
  '↵ Enter to run · ⇧ Shift+Enter for a new line': '↵ Enter để chạy · ⇧ Shift+Enter để xuống dòng',
  '  ·  ⚡ Interactive = terminal with approve/reject per edit':
    '  ·  ⚡ Tương tác = terminal, duyệt/từ chối từng thay đổi',
  'edits code': 'sửa code',
};

// Terms Vietnamese dev teams keep in English on purpose. Listing them here is how we distinguish
// "deliberately untranslated" from "someone forgot" — tests/i18n.test.cjs enforces that difference.
const I18N_VI_SAME = [
  'Review & QA',        // used verbatim in Vietnamese standups
  'Review code / PR',
  'Retrospective',
];
