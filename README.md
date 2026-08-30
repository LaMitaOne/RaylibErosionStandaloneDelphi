# RaylibErosionStandalone
RaylibErosionViewer (Delphi Port)   
    
A high-performance, threaded VCL component utilizing Raylib for off-screen rendering. Fully encapsulates the Terrain Erosion island demo.    
           
[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/LaMitaOne/RaylibErosionStandaloneDelphi)    
         
<img width="870" height="614" alt="Unbenannt" src="https://github.com/user-attachments/assets/7e56bb0f-319d-4c12-9f5e-c41b89d7d658" />
    
<img width="360" height="202" alt="azzqo3" src="https://github.com/user-attachments/assets/77901292-02a0-486c-ae63-d4f95f01c9ac" />
             
🚀 Features

    🧵 Threaded Architecture: Runs the entire Raylib Game Loop in a background thread, separating logic from the UI thread.
    🧩 Full Encapsulation: The entire engine (Erosion Math, RLights, Shaders) is packed into a single drop-in TWinControl.
    ⚡ Performance Boost: Increased performance by ~20+ FPS compared to standard VCL TTimer approaches. Timer done 31fps...
        Threaded now...
        ryzen4500u with vega up to 120fps was ok here, at desktop 380fps+ oO ehm yes really at rtx2060s :D 40% gpu 12% cpu at 380fps wtf,
        m3 dualcore 20fps he not likes it so much) 
    
🙏 Acknowledgements    
    
Original C++ Project by Delvix000.   
     
Port to delphi in folder RaylibErosionViewer, all combined in one file.    
Just copy the src\ressources folder to exe folder and...start    
