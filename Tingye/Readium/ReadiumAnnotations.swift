import Foundation
import UIKit
import ReadiumShared
import ReadiumNavigator

@MainActor
enum ReadiumAnnotations {
    static let userGroup = "tingye.user"
    static let speechGroup = "tingye.tts"
    static let searchGroup = "tingye.search"
    static let wavy: Decoration.Style.Id = "tingye.wavy"
    static let speech: Decoration.Style.Id = "tingye.speech"
    enum SelectionAction: Equatable { case highlight, bookmark, note }
    struct Batch {
        var decorations: [Decoration] = []
        var unresolved: [UUID] = []
    }
    static func style(color: String, kind: String) -> Decoration.Style {
        let tint = ReaderMark.uiColor(color)
        switch kind {
        case "underline": return .underline(tint: tint)
        case "wavy": return .init(id: wavy, config: Decoration.Style.HighlightConfig(tint: tint, isActive: false))
        default: return .highlight(tint: tint)
        }
    }
    static func templates() -> [Decoration.Style.Id: HTMLDecorationTemplate] {
        var templates = HTMLDecorationTemplate.defaultTemplates(alpha: 0.28)
        templates[speech] = HTMLDecorationTemplate(layout: .boxes, element: { decoration in
            let color = (decoration.style.config as? Decoration.Style.HighlightConfig)?.tint ?? UIColor(Theme.claySoft)
            return "<div class=\"ty-speech\" style=\"background:\(color.cssHex)\"/>"
        }, stylesheet: """
        .ty-speech { box-sizing:border-box;border-left:2px solid #D97757; }
        """)
        templates[wavy] = HTMLDecorationTemplate(layout: .boxes, element: { decoration in
            let config = decoration.style.config as? Decoration.Style.HighlightConfig
            let color = config?.tint ?? ReaderMark.uiColor("yellow")
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: &a)
            let hex = String(format: "%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
            return "<div class=\"ty-wavy\" style=\"--ty-wave:url('data:image/svg+xml,%3Csvg xmlns=%22http://www.w3.org/2000/svg%22 width=%228%22 height=%224%22%3E%3Cpath d=%22M0 2Q2 0 4 2T8 2%22 fill=%22none%22 stroke=%22%23\(hex)%22 stroke-width=%221.5%22/%3E%3C/svg%3E')\"/>"
        }, stylesheet: """
        .ty-wavy { background-image:var(--ty-wave);background-position:bottom;background-size:8px 4px;background-repeat:repeat-x; }
        [data-writing-mode="vertical-rl"].ty-wavy, [data-writing-mode="sideways-rl"].ty-wavy { background-position:left;background-size:4px 8px;background-repeat:repeat-y; }
        [data-writing-mode="vertical-lr"].ty-wavy, [data-writing-mode="sideways-lr"].ty-wavy { background-position:right;background-size:4px 8px;background-repeat:repeat-y; }
        """)
        return templates
    }
    static func decorations(_ highlights: [Highlight], bridge: LocatorBridge, mode: String) async throws -> Batch {
        var batch = Batch()
        for highlight in highlights {
            try Task.checkCancellation()
            do {
                let resolved = try await bridge.resolve(.init(highlight))
                guard resolved.precise, let locator = try await bridge.displayLocator(resolved.locator, mode: mode, requireRange: true) else {
                    batch.unresolved.append(highlight.id); continue
                }
                batch.decorations.append(Decoration(id: highlight.id.uuidString, locator: locator,
                                                    style: style(color: highlight.color, kind: highlight.style)))
            } catch is CancellationError { throw CancellationError() }
            catch { batch.unresolved.append(highlight.id) }
        }
        return batch
    }
    /// Locate the first visible code point, including when a long paragraph spans several pages.
    /// Also records `pageEnd`: the exclusive offset of the last code point still on this page,
    /// so read-aloud can turn as soon as that character has been spoken.
    /// DOM-order traversal works for scrolling, columns and vertical writing; all work is bounded.
    static let visibleRangeScript = #"""
    (() => {
      const body = document.body;
      if (!body) return null;
      const visible = range => Array.from(range.getClientRects()).some(r =>
        r.width > 0 && r.height > 0 && r.right > 0 && r.bottom > 0 && r.left < innerWidth && r.top < innerHeight);
      const css = el => {
        if (el === body) return 'body';
        if (!el.parentElement) return el.tagName.toLowerCase();
        const tag = el.tagName.toLowerCase();
        const peers = Array.from(el.parentElement.children).filter(e => e.tagName === el.tagName);
        return css(el.parentElement) + ' > ' + tag + ':nth-of-type(' + (peers.indexOf(el) + 1) + ')';
      };
      const point = (node, offset) => {
        const texts = Array.from(node.parentElement.childNodes).filter(n => n.nodeType === Node.TEXT_NODE);
        return {cssSelector:css(node.parentElement), textNodeIndex:texts.indexOf(node), charOffset:offset};
      };
      const afterViewport = range => {
        const box = range.getBoundingClientRect();
        return box.left >= innerWidth || box.top >= innerHeight;
      };
      const lastVisible = node => {
        const range = document.createRange();
        let lo = 0, hi = node.length, answer = -1;
        while (lo < hi) {
          let mid = (lo + hi) >> 1;
          if (mid > 0 && node.data.charCodeAt(mid) >= 0xDC00 && node.data.charCodeAt(mid) <= 0xDFFF) mid--;
          const size = node.data.codePointAt(mid) > 0xFFFF ? 2 : 1;
          range.setStart(node, mid); range.setEnd(node, Math.min(node.length, mid + size));
          if (visible(range)) { answer = mid; lo = mid + size; }
          else if (afterViewport(range)) hi = mid;
          else lo = mid + size;
        }
        return answer;
      };
      const walker = document.createTreeWalker(body, NodeFilter.SHOW_TEXT);
      let node, visited = 0, anchor = null, pageEnd = null, seen = false;
      while ((node = walker.nextNode()) && ++visited <= 12000) {
        if (!node.data.trim() || node.parentElement.closest('script,style,noscript,nav')) continue;
        const style = getComputedStyle(node.parentElement);
        if (style.visibility !== 'visible' || style.display === 'none' || style.opacity === '0') continue;
        const range = document.createRange(); range.selectNodeContents(node);
        if (!visible(range)) { if (seen) break; continue; }
        const last = lastVisible(node);
        if (last < 0) { if (seen) break; continue; }
        seen = true;
        const size = node.data.codePointAt(last) > 0xFFFF ? 2 : 1;
        pageEnd = point(node, last + size);
        if (!anchor) {
          let low = 0, high = node.length;
          while (high - low > 1) {
            const mid = Math.floor((low + high) / 2);
            range.setStart(node, low); range.setEnd(node, mid);
            if (visible(range)) high = mid; else low = mid;
          }
          if (low && node.data.charCodeAt(low) >= 0xDC00 && node.data.charCodeAt(low) <= 0xDFFF) low--;
          const end = low + (node.data.codePointAt(low) > 0xFFFF ? 2 : 1);
          anchor = {start:point(node, low), end:point(node, end)};
        }
      }
      return anchor ? {start:anchor.start, end:anchor.end, pageEnd} : null;
    })()
    """#
    /// Toolkit's selection carries quote/context; capture the actual range too, to disambiguate repeated text.
    static let selectionRangeScript = #"""
    (() => {
      const selection = window.getSelection();
      if (!selection || !selection.rangeCount) return null;
      const range = selection.getRangeAt(0);
      const css = el => {
        if (el.tagName.toLowerCase() === 'body') return 'body';
        const tag = el.tagName.toLowerCase();
        const peers = Array.from(el.parentElement.children).filter(e => e.tagName === el.tagName);
        return css(el.parentElement) + ' > ' + tag + ':nth-of-type(' + (peers.indexOf(el) + 1) + ')';
      };
      const point = (node, offset) => {
        if (node.nodeType !== Node.TEXT_NODE) return null;
        const texts = Array.from(node.parentElement.childNodes).filter(n => n.nodeType === Node.TEXT_NODE);
        return {cssSelector:css(node.parentElement),textNodeIndex:texts.indexOf(node),charOffset:offset};
      };
      const start = point(range.startContainer,range.startOffset), end = point(range.endContainer,range.endOffset);
      return start && end ? {start,end} : null;
    })()
    """#
}
