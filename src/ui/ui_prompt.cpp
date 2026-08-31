#include <mutex>
#include <filesystem>
#include <fstream>
#include <array>
#include <cstdint>

#include "recomp_ui.h"
#include "zelda_support.h"

#include "elements/ui_element.h"
#include "elements/ui_label.h"
#include "elements/ui_button.h"
#include "elements/ui_image.h"

struct {
    recompui::ContextId ui_context;
    recompui::Image* prompt_icon;
    bool prompt_icon_available = false;
    recompui::Element* prompt_progress_container;
    std::array<recompui::Image*, 4> prompt_progress_icons;
    recompui::Label* prompt_header;
    recompui::Label* prompt_label;
    recompui::Element* prompt_controls;
    recompui::Button* confirm_button;
    recompui::Button* cancel_button;
    std::function<void()> confirm_action;
    std::function<void()> cancel_action;
    std::string return_element_id;
    std::mutex mutex;
} prompt_state;

static constexpr const char* prompt_icon_src = "?/builtin/app_icon";

static bool try_read_file_bytes(const std::filesystem::path& path, std::vector<char>& out_bytes) {
    std::ifstream file(path, std::ios::binary);
    if (!file) {
        return false;
    }

    file.seekg(0, std::ios::end);
    std::streampos size = file.tellg();
    if (size <= 0) {
        return false;
    }
    file.seekg(0, std::ios::beg);

    out_bytes.resize(static_cast<size_t>(size));
    if (!file.read(out_bytes.data(), size)) {
        out_bytes.clear();
        return false;
    }

    return true;
}

static bool extract_png_from_ico(const std::vector<char>& ico_bytes, std::vector<char>& out_png_bytes) {
    auto read_u16 = [&](size_t offset) -> uint16_t {
        if (offset + 2 > ico_bytes.size()) {
            return 0;
        }
        return static_cast<uint16_t>(static_cast<uint8_t>(ico_bytes[offset])) |
               (static_cast<uint16_t>(static_cast<uint8_t>(ico_bytes[offset + 1])) << 8);
    };

    auto read_u32 = [&](size_t offset) -> uint32_t {
        if (offset + 4 > ico_bytes.size()) {
            return 0;
        }
        return static_cast<uint32_t>(static_cast<uint8_t>(ico_bytes[offset])) |
               (static_cast<uint32_t>(static_cast<uint8_t>(ico_bytes[offset + 1])) << 8) |
               (static_cast<uint32_t>(static_cast<uint8_t>(ico_bytes[offset + 2])) << 16) |
               (static_cast<uint32_t>(static_cast<uint8_t>(ico_bytes[offset + 3])) << 24);
    };

    if (ico_bytes.size() < 6) {
        return false;
    }

    const uint16_t reserved = read_u16(0);
    const uint16_t type = read_u16(2);
    const uint16_t count = read_u16(4);

    if (reserved != 0 || type != 1 || count == 0) {
        return false;
    }

    const size_t entries_offset = 6;
    const size_t entry_size = 16;
    if (entries_offset + entry_size * static_cast<size_t>(count) > ico_bytes.size()) {
        return false;
    }

    // Prefer the largest entry (typically 256x256). Note: width/height of 0 means 256.
    size_t best_entry_offset = 0;
    uint32_t best_area = 0;

    for (uint16_t i = 0; i < count; i++) {
        const size_t eoff = entries_offset + entry_size * static_cast<size_t>(i);
        const uint8_t w = static_cast<uint8_t>(ico_bytes[eoff + 0]);
        const uint8_t h = static_cast<uint8_t>(ico_bytes[eoff + 1]);
        const uint32_t width = (w == 0) ? 256u : static_cast<uint32_t>(w);
        const uint32_t height = (h == 0) ? 256u : static_cast<uint32_t>(h);
        const uint32_t area = width * height;
        const uint32_t bytes_in_res = read_u32(eoff + 8);
        const uint32_t image_offset = read_u32(eoff + 12);

        if (bytes_in_res == 0) {
            continue;
        }
        if (static_cast<uint64_t>(image_offset) + static_cast<uint64_t>(bytes_in_res) > ico_bytes.size()) {
            continue;
        }

        if (area > best_area) {
            best_area = area;
            best_entry_offset = eoff;
        }
    }

    if (best_area == 0) {
        return false;
    }

    const uint32_t bytes_in_res = read_u32(best_entry_offset + 8);
    const uint32_t image_offset = read_u32(best_entry_offset + 12);

    if (static_cast<uint64_t>(image_offset) + static_cast<uint64_t>(bytes_in_res) > ico_bytes.size()) {
        return false;
    }

    const char png_magic[] = { '\x89', 'P', 'N', 'G', '\r', '\n', '\x1a', '\n' };
    if (bytes_in_res < sizeof(png_magic)) {
        return false;
    }

    if (memcmp(ico_bytes.data() + image_offset, png_magic, sizeof(png_magic)) != 0) {
        // This ICO entry is not PNG-compressed (likely DIB). We currently only support PNG entries here.
        return false;
    }

    out_png_bytes.assign(ico_bytes.begin() + image_offset, ico_bytes.begin() + image_offset + bytes_in_res);
    return true;
}

static bool ensure_prompt_icon_queued() {
    static bool queued = false;
    static bool available = false;
    if (queued) {
        return available;
    }

    queued = true;

    std::vector<char> bytes;
    // Use the 256.ico file as the source, extracting the embedded PNG image.
    const std::filesystem::path icon_ico_path = zelda64::get_program_path() / "icons" / "256.ico";
    if (!try_read_file_bytes(icon_ico_path, bytes)) {
        available = false;
        return available;
    }

    std::vector<char> extracted_png;
    if (!extract_png_from_ico(bytes, extracted_png)) {
        available = false;
        return available;
    }

    recompui::queue_image_from_bytes_file(prompt_icon_src, extracted_png);
    available = true;
    return available;
}

static void update_prompt_progress_locked(int completed, int total) {
    total = std::clamp(total, 0, (int)prompt_state.prompt_progress_icons.size());
    completed = std::clamp(completed, 0, total);

    if (total <= 1) {
        prompt_state.prompt_progress_container->set_display(recompui::Display::None);
        return;
    }

    prompt_state.prompt_progress_container->set_display(recompui::Display::Flex);
    // Hide the single icon when showing per-player icon count.
    prompt_state.prompt_icon->set_display(recompui::Display::None);

    for (int i = 0; i < (int)prompt_state.prompt_progress_icons.size(); i++) {
        auto* icon = prompt_state.prompt_progress_icons[(size_t)i];
        icon->set_display(i < completed ? recompui::Display::Block : recompui::Display::None);
    }
}

void run_confirm_callback() {
    std::function<void()> confirm_action;
    {
        std::lock_guard lock{ prompt_state.mutex };
        confirm_action = std::move(prompt_state.confirm_action);
    }
    if (confirm_action) {
        confirm_action();
    }
    recompui::hide_context(prompt_state.ui_context);

    // TODO nav: focus on return_element_id
    // or just remove it as the usage of the prompt can change now
}

void run_cancel_callback() {
    std::function<void()> cancel_action;
    {
        std::lock_guard lock{ prompt_state.mutex };
        cancel_action = std::move(prompt_state.cancel_action);
    }
    if (cancel_action) {
        cancel_action();
    }
    recompui::hide_context(prompt_state.ui_context);

    // TODO nav: focus on return_element_id
    // or just remove it as the usage of the prompt can change now
}

void recompui::init_prompt_context() {
    ContextId context = create_context();

    std::lock_guard lock{ prompt_state.mutex };

    context.open();

    prompt_state.ui_context = context;

    Element* window = context.create_element<Element>(context.get_root_element());
    window->set_display(Display::Flex);
    window->set_flex_direction(FlexDirection::Column);
    window->set_background_color({0, 0, 0, 0});

    Element* prompt_overlay = context.create_element<Element>(window);
    prompt_overlay->set_background_color(Color{ 190, 184, 219, 25 });
    prompt_overlay->set_position(Position::Absolute);
    prompt_overlay->set_top(0);
    prompt_overlay->set_right(0);
    prompt_overlay->set_bottom(0);
    prompt_overlay->set_left(0);

    Element* prompt_content_wrapper = context.create_element<Element>(window);
    prompt_content_wrapper->set_display(Display::Flex);
    prompt_content_wrapper->set_position(Position::Absolute);
    prompt_content_wrapper->set_top(0);
    prompt_content_wrapper->set_right(0);
    prompt_content_wrapper->set_bottom(0);
    prompt_content_wrapper->set_left(0);
    prompt_content_wrapper->set_align_items(AlignItems::Center);
    prompt_content_wrapper->set_justify_content(JustifyContent::Center);

    Element* prompt_content = context.create_element<Element>(prompt_content_wrapper);
    prompt_content->set_display(Display::Flex);
    prompt_content->set_position(Position::Relative);
    prompt_content->set_flex(1.0f, 1.0f);
    prompt_content->set_flex_basis(100, Unit::Percent);
    prompt_content->set_flex_direction(FlexDirection::Column);
    prompt_content->set_width(100, Unit::Percent);
    prompt_content->set_max_width(700, Unit::Dp);
    prompt_content->set_height_auto();
    prompt_content->set_margin_auto();
    prompt_content->set_border_width(1.1, Unit::Dp);
    prompt_content->set_border_radius(16, Unit::Dp);
    prompt_content->set_border_color(Color{ 255, 255, 255, 51 });
    prompt_content->set_background_color(Color{ 8, 7, 13, 229 });

    prompt_state.prompt_icon_available = ensure_prompt_icon_queued();
    prompt_state.prompt_icon = context.create_element<Image>(prompt_content, prompt_icon_src);
    prompt_state.prompt_icon->set_width(96, Unit::Dp);
    prompt_state.prompt_icon->set_height(96, Unit::Dp);
    prompt_state.prompt_icon->set_margin_top(24, Unit::Dp);
    prompt_state.prompt_icon->set_margin_left_auto();
    prompt_state.prompt_icon->set_margin_right_auto();
    prompt_state.prompt_icon->set_display(Display::None);

    prompt_state.prompt_progress_container = context.create_element<Element>(prompt_content);
    prompt_state.prompt_progress_container->set_display(Display::None);
    prompt_state.prompt_progress_container->set_flex_direction(FlexDirection::Row);
    prompt_state.prompt_progress_container->set_justify_content(JustifyContent::Center);
    prompt_state.prompt_progress_container->set_gap(10, Unit::Dp);
    prompt_state.prompt_progress_container->set_margin_top(12, Unit::Dp);
    prompt_state.prompt_progress_container->set_margin_left_auto();
    prompt_state.prompt_progress_container->set_margin_right_auto();

    for (size_t i = 0; i < prompt_state.prompt_progress_icons.size(); i++) {
        auto* icon = context.create_element<Image>(prompt_state.prompt_progress_container, prompt_icon_src);
        icon->set_width(64, Unit::Dp);
        icon->set_height(64, Unit::Dp);
        icon->set_display(Display::None);
        prompt_state.prompt_progress_icons[i] = icon;
    }
    
    prompt_state.prompt_header = context.create_element<Label>(prompt_content, "", LabelStyle::Large);
    prompt_state.prompt_header->set_margin(24, Unit::Dp);

    prompt_state.prompt_label = context.create_element<Label>(prompt_content, "", LabelStyle::Small);
    prompt_state.prompt_label->set_margin(24, Unit::Dp);
    prompt_state.prompt_label->set_margin_top(0);
    
    prompt_state.prompt_controls = context.create_element<Element>(prompt_content);
    
    prompt_state.prompt_controls->set_display(Display::Flex);
    prompt_state.prompt_controls->set_flex_direction(FlexDirection::Row);
    prompt_state.prompt_controls->set_justify_content(JustifyContent::Center);
    prompt_state.prompt_controls->set_padding_top(24, Unit::Dp);
    prompt_state.prompt_controls->set_padding_bottom(24, Unit::Dp);
    prompt_state.prompt_controls->set_padding_left(12, Unit::Dp);
    prompt_state.prompt_controls->set_padding_right(12, Unit::Dp);
    prompt_state.prompt_controls->set_border_top_width(1.1, Unit::Dp);
    prompt_state.prompt_controls->set_border_top_color({ 255, 255, 255, 25 });

    prompt_state.confirm_button = context.create_element<Button>(prompt_state.prompt_controls, "", ButtonStyle::Primary);
    prompt_state.confirm_button->set_min_width(185.0f, Unit::Dp);
    prompt_state.confirm_button->set_margin_top(0);
    prompt_state.confirm_button->set_margin_bottom(0);
    prompt_state.confirm_button->set_margin_left(12, Unit::Dp);
    prompt_state.confirm_button->set_margin_right(12, Unit::Dp);
    prompt_state.confirm_button->set_text_align(TextAlign::Center);
    prompt_state.confirm_button->set_color(Color{ 204, 204, 204, 255 });
    prompt_state.confirm_button->add_pressed_callback(run_confirm_callback);
    
    Style* confirm_hover_style = prompt_state.confirm_button->get_hover_style();
    confirm_hover_style->set_border_color(Color{ 69, 208, 67, 255 });
    confirm_hover_style->set_background_color(Color{ 69, 208, 67, 76 });
    confirm_hover_style->set_color(Color{ 242, 242, 242, 255 });
    
    Style* confirm_focus_style = prompt_state.confirm_button->get_focus_style();
    confirm_focus_style->set_border_color(Color{ 69, 208, 67, 255 });
    confirm_focus_style->set_background_color(Color{ 69, 208, 67, 76 });
    confirm_focus_style->set_color(Color{ 242, 242, 242, 255 });

    prompt_state.cancel_button = context.create_element<Button>(prompt_state.prompt_controls, "", ButtonStyle::Primary);
    prompt_state.cancel_button->set_min_width(185.0f, Unit::Dp);
    prompt_state.cancel_button->set_margin_top(0);
    prompt_state.cancel_button->set_margin_bottom(0);
    prompt_state.cancel_button->set_margin_left(12, Unit::Dp);
    prompt_state.cancel_button->set_margin_right(12, Unit::Dp);
    prompt_state.cancel_button->set_text_align(TextAlign::Center);
    prompt_state.cancel_button->set_color(Color{ 204, 204, 204, 255 });
    prompt_state.cancel_button->add_pressed_callback(run_cancel_callback);
    
    Style* cancel_hover_style = prompt_state.cancel_button->get_hover_style();
    cancel_hover_style->set_border_color(Color{ 248, 96, 57, 255 });
    cancel_hover_style->set_background_color(Color{ 248, 96, 57, 76 });
    cancel_hover_style->set_color(Color{ 242, 242, 242, 255 });

    Style* cancel_focus_style = prompt_state.cancel_button->get_focus_style();
    cancel_focus_style->set_border_color(Color{ 248, 96, 57, 255 });
    cancel_focus_style->set_background_color(Color{ 248, 96, 57, 76 });
    cancel_focus_style->set_color(Color{ 242, 242, 242, 255 });


    context.close();
}

void style_button(recompui::Button* button, recompui::ButtonVariant variant) {
    recompui::Color button_color{};

    switch (variant) {
        case recompui::ButtonVariant::Primary:
            button_color = { 185, 125, 242, 255 };
            break;
        case recompui::ButtonVariant::Secondary:
            button_color = { 23, 214, 232, 255 };
            break;
        case recompui::ButtonVariant::Tertiary:
            button_color = { 242, 242, 242, 255 };
            break;
        case recompui::ButtonVariant::Success:
            button_color = { 69, 208, 67, 255 };
            break;
        case recompui::ButtonVariant::Error:
            button_color = { 248, 96, 57, 255 };
            break;
        case recompui::ButtonVariant::Warning:
            button_color = { 233, 205, 53, 255 };
            break;
        default:
            assert(false);
            break;
    }

    recompui::Color border_color = button_color;
    recompui::Color background_color = button_color;
    border_color.a = 0.8f * 255;
    background_color.a = 0.05f * 255;
    button->set_border_color(border_color);
    button->set_background_color(background_color);
    
    recompui::Color hover_border_color = button_color;
    recompui::Color hover_background_color = button_color;
    hover_border_color.a = 255;
    hover_background_color.a = 0.3f * 255;
    recompui::Style* hover_style = button->get_hover_style();
    hover_style->set_border_color(hover_border_color);
    hover_style->set_background_color(hover_background_color);
    
    recompui::Style* focus_style = button->get_focus_style();
    focus_style->set_border_color(hover_border_color);
    focus_style->set_background_color(hover_background_color);

    recompui::Color disabled_color { 255, 255, 255, 0.6f * 255 };
    recompui::Style* disabled_style = button->get_disabled_style();
    disabled_style->set_color(disabled_color);
}

// Must be called while prompt_state.mutex is locked.
void show_prompt(std::function<void()>& prev_cancel_action, bool focus_on_cancel) {
    if (focus_on_cancel) {
        prompt_state.ui_context.set_autofocus_element(prompt_state.cancel_button);
    }
    else {
        prompt_state.ui_context.set_autofocus_element(prompt_state.confirm_button);
    }

    if (!recompui::is_context_shown(prompt_state.ui_context)) {
        recompui::show_context(prompt_state.ui_context, "");
    }
    else {
        // Call the previous cancel action to effectively close the previous prompt.
        if (prev_cancel_action) {
            prev_cancel_action();
        }
    }
}

void recompui::open_choice_prompt(
    const std::string& header_text,
    const std::string& content_text,
    const std::string& confirm_label_text,
    const std::string& cancel_label_text,
    std::function<void()> confirm_action,
    std::function<void()> cancel_action,
    ButtonVariant confirm_variant,
    ButtonVariant cancel_variant,
    bool focus_on_cancel,
    const std::string& return_element_id
) {
    std::lock_guard lock{ prompt_state.mutex };

    std::function<void()> prev_cancel_action = std::move(prompt_state.cancel_action);

    ContextId prev_context = try_close_current_context();

    prompt_state.ui_context.open();

    prompt_state.prompt_header->set_text(header_text);
    prompt_state.prompt_label->set_text(content_text);
    prompt_state.prompt_icon->set_display(Display::None);
    prompt_state.prompt_progress_container->set_display(Display::None);
    prompt_state.prompt_controls->set_display(Display::Flex);
    prompt_state.confirm_button->set_display(Display::Block);
    prompt_state.cancel_button->set_display(Display::Block);
    prompt_state.confirm_button->set_text(confirm_label_text);
    prompt_state.cancel_button->set_text(cancel_label_text);
    prompt_state.confirm_action = confirm_action;
    prompt_state.cancel_action = cancel_action;
    prompt_state.return_element_id = return_element_id;

    style_button(prompt_state.confirm_button, confirm_variant);
    style_button(prompt_state.cancel_button, cancel_variant);

    prompt_state.ui_context.close();

    if (prev_context != ContextId::null()) {
        prev_context.open();
    }

    show_prompt(prev_cancel_action, focus_on_cancel);
}

void recompui::open_info_prompt(
    const std::string& header_text,
    const std::string& content_text,
    const std::string& okay_label_text,
    std::function<void()> okay_action,
    ButtonVariant okay_variant,
    const std::string& return_element_id
) {
    std::lock_guard lock{ prompt_state.mutex };

    std::function<void()> prev_cancel_action = std::move(prompt_state.cancel_action);

    ContextId prev_context = try_close_current_context();

    prompt_state.ui_context.open();

    prompt_state.prompt_header->set_text(header_text);
    prompt_state.prompt_label->set_text(content_text);
    prompt_state.prompt_icon->set_display(Display::None);
    prompt_state.prompt_progress_container->set_display(Display::None);
    prompt_state.prompt_controls->set_display(Display::Flex);
    prompt_state.confirm_button->set_display(Display::None);
    prompt_state.cancel_button->set_display(Display::Block);
    prompt_state.cancel_button->set_text(okay_label_text);
    prompt_state.confirm_action = {};
    prompt_state.cancel_action = okay_action;
    prompt_state.return_element_id = return_element_id;

    style_button(prompt_state.cancel_button, okay_variant);

    prompt_state.ui_context.close();

    if (prev_context != ContextId::null()) {
        prev_context.open();
    }

    show_prompt(prev_cancel_action, true);
}

void recompui::open_notification(
    const std::string& header_text,
    const std::string& content_text,
    const std::string& return_element_id
) {
    std::lock_guard lock{ prompt_state.mutex };

    std::function<void()> prev_cancel_action = std::move(prompt_state.cancel_action);

    ContextId prev_context = try_close_current_context();

    prompt_state.ui_context.open();

    prompt_state.prompt_header->set_text(header_text);
    prompt_state.prompt_label->set_text(content_text);
    prompt_state.prompt_icon->set_display(prompt_state.prompt_icon_available ? Display::Block : Display::None);
    prompt_state.prompt_progress_container->set_display(Display::None);
    prompt_state.prompt_controls->set_display(Display::None);
    prompt_state.confirm_button->set_display(Display::None);
    prompt_state.cancel_button->set_display(Display::None);
    prompt_state.confirm_action = {};
    prompt_state.cancel_action = {};
    prompt_state.return_element_id = return_element_id;

    prompt_state.ui_context.close();

    if (prev_context != ContextId::null()) {
        prev_context.open();
    }

    show_prompt(prev_cancel_action, false);
}

void recompui::set_prompt_progress(int completed, int total) {
    std::lock_guard lock{ prompt_state.mutex };
    prompt_state.ui_context.open();
    update_prompt_progress_locked(completed, total);
    prompt_state.ui_context.close();
}

void recompui::clear_prompt_progress() {
    std::lock_guard lock{ prompt_state.mutex };
    prompt_state.ui_context.open();
    prompt_state.prompt_progress_container->set_display(Display::None);
    prompt_state.prompt_icon->set_display(prompt_state.prompt_icon_available ? Display::Block : Display::None);
    prompt_state.ui_context.close();
}

void recompui::close_prompt() {
    std::lock_guard lock{ prompt_state.mutex };

    if (recompui::is_context_shown(prompt_state.ui_context)) {
        if (prompt_state.cancel_action) {
            prompt_state.cancel_action();
        }

        recompui::hide_context(prompt_state.ui_context);
    }
}

bool recompui::is_prompt_open() {
    std::lock_guard lock{ prompt_state.mutex };

	return recompui::is_context_shown(prompt_state.ui_context);
}
