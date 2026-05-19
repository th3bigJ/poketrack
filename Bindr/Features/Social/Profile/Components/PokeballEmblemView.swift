import SwiftUI

struct PokeballEmblemView: View {
    var size: CGFloat = 14
    
    var body: some View {
        ZStack {
            // Pokéball outer circle
            Circle()
                .fill(.black)
            
            // Top half red
            Circle()
                .trim(from: 0.0, to: 0.5)
                .fill(Color(hex: "E05252")) // Beautiful vibrant Pokéball red
                .rotationEffect(.degrees(180))
            
            // Bottom half white
            Circle()
                .trim(from: 0.5, to: 1.0)
                .fill(Color.white)
                .rotationEffect(.degrees(180))
            
            // Horizontal separator line
            Rectangle()
                .fill(.black)
                .frame(height: size * 0.1)
            
            // Center circle black outline
            Circle()
                .fill(.black)
                .frame(width: size * 0.38, height: size * 0.38)
            
            // Center button white
            Circle()
                .fill(Color.white)
                .frame(width: size * 0.22, height: size * 0.22)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(Color.black.opacity(0.85), lineWidth: size * 0.06)
        )
        .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 1)
    }
}
