import XCTest

final class TemplateReadingFlowTests: TypographyTestSupport {
    func testNestedTemplateHierarchyAndModeControlsSurviveRevealAndRotation() throws {
        let app = application()
        defer { XCUIDevice.shared.orientation = .portrait }
        let front = """
        <style>
        .paper { max-width:520px; margin:auto }
        .paper-label { display:inline-block; font-size:12px; background:#333; color:white; padding:2px 4px; border-radius:3px; cursor:pointer }
        .paper-modes { margin:12px 0 }
        .paper-choice { display:inline-block; font-size:12px; padding:3px 10px; border:1px solid #999; border-radius:10px; cursor:pointer }
        .paper-choice.active { background:green; color:white }
        .paper-heading { font-size:32px; margin:12px 0 }
        .paper-example { font-size:24px; margin:12px 0 }
        .paper-example em { color:green; font-style:normal }
        .paper[data-mode="example"] .paper-heading { display:none }
        .paper[data-mode="heading"] .paper-example { display:none }
        </style>
        <div class="paper" data-mode="both">
          <div class="paper-label">language</div>
          <div class="paper-modes"><span role="button" class="paper-choice" data-mode="heading">Heading</span>
          <span role="button" class="paper-choice" data-mode="example">Examples</span>
          <span role="button" class="paper-choice active" data-mode="both">Both</span></div>
          <div class="paper-heading">A useful expression</div>
          <div class="paper-example">We will <em>send the final document</em> tomorrow morning.</div>
        </div>
        <script>
        (()=>{
          const panel=document.querySelector('.paper'),qa=document.getElementById('qa');
          for(const item of panel.querySelectorAll('.paper-choice'))item.addEventListener('click',()=>{
            panel.dataset.mode=item.dataset.mode;
            for(const button of panel.querySelectorAll('.paper-choice'))button.className='paper-choice'+(button===item?' active':'');
          });
          qa.addEventListener('study-layout',()=>{
            let out=document.getElementById('paper-result');
            if(!out){out=document.createElement('div');out.id='paper-result';out.style='position:fixed;bottom:0;left:0;font-size:12px;background:white;color:black';document.body.append(out);}
            const font=e=>parseFloat(getComputedStyle(e).fontSize),heading=panel.querySelector('.paper-heading'),example=panel.querySelector('.paper-example');
            const controls=Array.from(panel.querySelectorAll('.paper-choice'));
            const ratio=font(example)/font(heading),badge=font(panel.querySelector('.paper-label'));
            const ok=ratio>=.74&&ratio<=.76&&font(example)>=26&&font(example.querySelector('em'))===font(example)&&badge>=12&&badge<=23&&controls.every(e=>font(e)>=20&&e.getBoundingClientRect().width>=44&&e.getBoundingClientRect().height>=44)&&panel.getBoundingClientRect().width>Math.min(700,innerWidth-80)&&document.documentElement.scrollWidth<=innerWidth+1;
            out.textContent=ok?'Template verified '+panel.dataset.mode+' '+(innerWidth>innerHeight?'landscape':'portrait')+(document.getElementById('paper-answer')?' answer':' question'):'Template failed '+JSON.stringify({ratio,badge,font:font(example),width:panel.getBoundingClientRect().width});
          });
        })();
        </script>
        """
        try addNote(front: front, back: "<div id=\"paper-answer\">日本語の意味と例文の説明</div>", in: app)
        XCUIDevice.shared.orientation = .landscapeLeft
        requireTestCondition("Template review starts in landscape", in: app) { app.frame.width > app.frame.height }
        tapTestControl(app.buttons.matching(identifier: "deck-1"), in: app)
        let web = try XCTUnwrap(waitForTestCardWebView(in: app))
        _ = try XCTUnwrap(waitForTestControl(web.staticTexts.matching(NSPredicate(format: "label == %@", "A useful expression")), in: app, timeout: 60, purpose: .observation))
        expect("Template verified both landscape question", in: web, app: app)
        capture("Nested authored hierarchy and controls landscape", in: app)
        tapTestControl(web.buttons.matching(NSPredicate(format: "label == %@", "Examples")), in: app)
        expect("Template verified example landscape question", in: web, app: app)
        tapTestControl(web.buttons.matching(NSPredicate(format: "label == %@", "Both")), in: app)
        expect("Template verified both landscape question", in: web, app: app)
        XCUIDevice.shared.orientation = .portrait
        expect("Template verified both portrait question", in: web, app: app)
        capture("Nested authored hierarchy and controls portrait", in: app)
        XCUIDevice.shared.orientation = .landscapeLeft
        expect("Template verified both landscape question", in: web, app: app)
        tapTestControl(app.buttons.matching(identifier: "reveal"), in: app)
        expect("Template verified both landscape answer", in: web, app: app)
        _ = waitForTestControl(app.buttons.matching(identifier: "answer-2"), in: app)
        capture("Nested authored hierarchy after answer reveal", in: app)
    }

    private func expect(_ label: String, in web: XCUIElement, app: XCUIApplication) {
        requireTestCondition(label, in: app) {
            web.staticTexts.matching(NSPredicate(format: "label == %@", label)).count == 1
        }
    }
}
