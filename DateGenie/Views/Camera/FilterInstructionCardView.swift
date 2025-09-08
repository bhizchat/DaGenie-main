import SwiftUI

struct FilterInstructionCardView: View {
	let title: String
	let uiThumbnailName: String?
	let onDismiss: () -> Void

	@State private var didScheduleAutoDismiss = false

	var body: some View {
		VStack(spacing: 12) {
			HStack(alignment: .top, spacing: 12) {
				Text(title)
					.font(.system(size: 18, weight: .semibold))
					.foregroundColor(.white)
				Spacer()
				Button(action: onDismiss) {
					Image(systemName: "xmark")
						.font(.system(size: 14, weight: .bold))
						.foregroundColor(.white.opacity(0.9))
						.padding(6)
						.background(Color.white.opacity(0.12))
						.clipShape(Circle())
				}
			}

			VStack(alignment: .leading, spacing: 10) {
				instructionRow(icon: "person.2.fill", text: "Frame 1–2 people waist‑up. Leave some space near the bottom for the sticker.")
				instructionRow(icon: "hands.sparkles.fill", text: "Pose like the mascots: face the camera and raise both fists at chest level.")
				instructionRow(icon: "camera.circle.fill", text: "Pinch to resize, drag to move, rotate with two fingers. Tap the shutter to capture.")
			}

			if let name = uiThumbnailName, let ui = UIImage(named: name) {
				HStack(spacing: 10) {
					Image(uiImage: ui)
						.resizable()
						.scaledToFit()
						.frame(width: 56, height: 56)
						.cornerRadius(8)
					Text("Example placement")
						.font(.system(size: 13, weight: .medium))
						.foregroundColor(.white.opacity(0.9))
					Spacer()
				}
			}

			Button(action: onDismiss) {
				Text("Got it")
					.font(.system(size: 16, weight: .semibold))
					.frame(maxWidth: .infinity)
					.padding(.vertical, 10)
					.background(Color.white.opacity(0.2))
					.cornerRadius(10)
					.foregroundColor(.white)
			}
		}
		.padding(16)
		.background(
			RoundedRectangle(cornerRadius: 16, style: .continuous)
				.fill(Color.black.opacity(0.6))
		)
		.padding(.horizontal, 16)
		.onAppear {
			guard !didScheduleAutoDismiss else { return }
			didScheduleAutoDismiss = true
			DispatchQueue.main.asyncAfter(deadline: .now() + 7) { onDismiss() }
		}
	}

	@ViewBuilder
	private func instructionRow(icon: String, text: String) -> some View {
		HStack(alignment: .top, spacing: 10) {
			Image(systemName: icon)
				.font(.system(size: 18, weight: .semibold))
				.frame(width: 22)
				.foregroundColor(.white)
			Text(text)
				.font(.system(size: 14))
				.foregroundColor(.white)
		}
	}
}


