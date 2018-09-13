//
//  BasicVideoFilter.swift
//  VideoCast
//
//  Created by Tomohiro Matsuzawa on 2018/02/13.
//  Copyright © 2018年 CyberAgent, Inc. All rights reserved.
//

import Foundation
import GLKit
#if !targetEnvironment(simulator)
import Metal
#endif

open class BasicVideoFilter: IVideoFilter {
    #if targetEnvironment(simulator)
    open var vertexKernel: String? {
        return kernel(language: .GL_ES2_3, target: filterLanguage, kernelstr: """
attribute vec2 aPos;
attribute vec2 aCoord;
varying vec2   vCoord;
uniform mat4   uMat;
void main(void) {
    gl_Position = uMat * vec4(aPos,0.,1.);
    vCoord = aCoord;
}
""")
    }

    open var pixelKernel: String? {
        return kernel(language: .GL_ES2_3, target: filterLanguage, kernelstr: """
precision mediump float;
varying vec2      vCoord;
uniform sampler2D uTex0;
void main(void) {
    gl_FragData[0] = texture2D(uTex0, vCoord);
}
""")
    }

    open var filterLanguage: FilterLanguage = .GL_ES2_3

    open var program: GLuint = 0
    #else
    open var vertexFunc: String {
        return "basic_vertex"
    }

    open var fragmentFunc: String {
        return "bgra_fragment"
    }

    open var renderPipelineState: MTLRenderPipelineState?

    open var renderEncoder: MTLRenderCommandEncoder?
    #endif

    open var matrix = GLKMatrix4Identity

    open var dimensions = CGSize.zero

    open var initialized = false

    open var name: String {
        return ""
    }

    #if targetEnvironment(simulator)
    private var vao: GLuint = 0
    private var uMatrix: Int32 = 0
    #else
    open var piplineDescripter: String? {
        return nil
    }

    private var device = DeviceManager.device
    #endif

    private var bound = false

    public init() {

    }

    deinit {
        #if targetEnvironment(simulator)
        glDeleteProgram(program)
        glDeleteVertexArraysOES(1, &vao)
        #endif
    }

    // swiftlint:disable:next function_body_length
    open func initialize() {
        #if targetEnvironment(simulator)
        switch filterLanguage {
        case .GL_ES2_3, .GL_2:
            guard let vertexKernel = vertexKernel, let pixelKernel = pixelKernel else {
                Logger.debug("unexpected return")
                break
            }

            program = buildProgram(vertex: vertexKernel, fragment: pixelKernel)
            glGenVertexArraysOES(1, &vao)
            glBindVertexArrayOES(vao)
            uMatrix = glGetUniformLocation(program, "uMat")
            let attrpos = glGetAttribLocation(program, "aPos")
            let attrtex = glGetAttribLocation(program, "aCoord")
            let unitex = glGetUniformLocation(program, "uTex0")
            glUniform1i(unitex, 0)
            glEnableVertexAttribArray(GLuint(attrpos))
            glEnableVertexAttribArray(GLuint(attrtex))
            glVertexAttribPointer(
                GLuint(attrpos), GLint(BUFFER_SIZE_POSITION),
                GLenum(GL_FLOAT), GLboolean(GL_FALSE),
                GLsizei(BUFFER_STRIDE), BUFFER_OFFSET_POSITION)
            glVertexAttribPointer(
                GLuint(attrtex), GLint(BUFFER_SIZE_POSITION),
                GLenum(GL_FLOAT), GLboolean(GL_FALSE),
                GLsizei(BUFFER_STRIDE), BUFFER_OFFSET_TEXTURE)
            initialized = true
        case .GL_3:
            break
        }
        #else
        let defaultLibrary: MTLLibrary!
        guard let libraryFile = Bundle(for: type(of: self)).path(forResource: "default", ofType: "metallib") else {
            fatalError(">> ERROR: Couldnt find a default shader library path")
        }
        do {
            try defaultLibrary = device.makeLibrary(filepath: libraryFile)
        } catch {
            fatalError(">> ERROR: Couldnt create a default shader library")
        }

        // read the vertex and fragment shader functions from the library
        let vertexProgram = defaultLibrary.makeFunction(name: vertexFunc)
        let fragmentprogram = defaultLibrary.makeFunction(name: fragmentFunc)

        //  create a pipeline state descriptor
        let renderPipelineDescriptor = MTLRenderPipelineDescriptor()
        if let piplineDescripter = piplineDescripter {
            renderPipelineDescriptor.label = piplineDescripter
        }

        // set pixel formats that match the framebuffer we are drawing into
        renderPipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        // set the vertex and fragment programs
        renderPipelineDescriptor.vertexFunction = vertexProgram
        renderPipelineDescriptor.fragmentFunction = fragmentprogram

        do {
            // generate the pipeline state
            try renderPipelineState = device.makeRenderPipelineState(descriptor: renderPipelineDescriptor)
        } catch {
            fatalError("failed to generate the pipeline state \(error)")
        }
        initialized = true
        #endif
    }

    open func bind() {
        #if targetEnvironment(simulator)
        switch filterLanguage {
        case .GL_ES2_3, .GL_2:
            if !bound {
                if !initialized {
                    initialize()
                }
                glUseProgram(program)
                glBindVertexArrayOES(vao)
            }
            glUniformMatrix4fv(uMatrix, 1, GLboolean(GL_FALSE), matrix.array)
        case .GL_3:
            break
        }
        #else
        if !bound {
            if !initialized {
                initialize()
            }
        }
        #endif
    }

    #if !targetEnvironment(simulator)
    open func render(_ renderEncoder: MTLRenderCommandEncoder) {
        guard let renderPipelineState = renderPipelineState else { return }
        // set the pipeline state object which contains its precompiled shaders
        renderEncoder.setRenderPipelineState(renderPipelineState)

        // set the model view project matrix data
        if #available(iOS 8.3, *) {
            renderEncoder.setVertexBytes(&matrix, length: MemoryLayout<GLKMatrix4>.size, index: 1)
        } else {
            let buffer = device.makeBuffer(bytes: &matrix,
                                                      length: MemoryLayout<GLKMatrix4>.size,
                                                      options: [])
            renderEncoder.setVertexBuffer(buffer, offset: 0, index: 1)
        }
    }
    #endif

    open func unbind() {
        bound = false
    }
}
